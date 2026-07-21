#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cmath>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <memory>
#include <mutex>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <unitree/robot/channel/channel_factory.hpp>
#include <unitree/robot/go2/sport/sport_client.hpp>

namespace {

std::atomic<bool> g_shutdown_requested{false};

struct Options {
    std::string iface = "eth0";
    std::string socket_path = "/tmp/go2_motion_daemon.sock";
    int watchdog_ms = 500;
    double max_vx = 0.30;
    double max_vy = 0.0;
    double max_yaw = 0.30;
    bool enable_real_move = false;
};

struct Command {
    std::string type;
    int seq = 0;
    double vx = 0.0;
    double vy = 0.0;
    double yaw = 0.0;
};

void SignalHandler(int) {
    g_shutdown_requested.store(true);
}

double ParseDouble(const std::string &value, const std::string &name) {
    char *end = nullptr;
    const double parsed = std::strtod(value.c_str(), &end);
    if (end == value.c_str() || *end != '\0') {
        throw std::runtime_error("invalid numeric value for " + name + ": " + value);
    }
    return parsed;
}

int ParseInt(const std::string &value, const std::string &name) {
    char *end = nullptr;
    const long parsed = std::strtol(value.c_str(), &end, 10);
    if (end == value.c_str() || *end != '\0') {
        throw std::runtime_error("invalid integer value for " + name + ": " + value);
    }
    return static_cast<int>(parsed);
}

Options ParseArgs(int argc, char **argv) {
    Options options;
    for (int i = 1; i < argc; ++i) {
        const std::string arg(argv[i]);
        auto require_value = [&](const std::string &name) -> std::string {
            if (i + 1 >= argc) {
                throw std::runtime_error(name + " requires a value");
            }
            return argv[++i];
        };

        if (arg == "--iface") {
            options.iface = require_value(arg);
        } else if (arg == "--socket-path") {
            options.socket_path = require_value(arg);
        } else if (arg == "--watchdog-ms") {
            options.watchdog_ms = ParseInt(require_value(arg), arg);
        } else if (arg == "--max-vx") {
            options.max_vx = ParseDouble(require_value(arg), arg);
        } else if (arg == "--max-vy") {
            options.max_vy = ParseDouble(require_value(arg), arg);
        } else if (arg == "--max-yaw") {
            options.max_yaw = ParseDouble(require_value(arg), arg);
        } else if (arg == "--enable-real-move") {
            options.enable_real_move = true;
        } else {
            throw std::runtime_error("unknown argument: " + arg);
        }
    }
    return options;
}

void ValidateRealMoveGuards(const Options &options) {
    if (!options.enable_real_move) {
        return;
    }
    const char *ack = std::getenv("GO2_REAL_MOVE_ACK");
    if (ack == nullptr || std::string(ack) != "YES") {
        throw std::runtime_error("real move requires GO2_REAL_MOVE_ACK=YES");
    }
    if (options.max_vx > 0.50 || options.max_vy != 0.0 ||
        options.max_yaw > 0.30 || options.watchdog_ms > 500) {
        throw std::runtime_error(
            "real move refused: require max_vx<=0.50 max_vy==0 "
            "max_yaw<=0.30 watchdog_ms<=500");
    }
    std::cout << "==================================================\n"
              << "WARNING: REAL GO2 MOVE ENABLED\n"
              << "Ensure:\n"
              << "- GO2 is in an open area\n"
              << "- emergency stop is available\n"
              << "- Safety Gate is disabled before startup\n"
              << "- test only short supervised commands\n"
              << "==================================================\n";
}

std::string JsonBool(bool value) {
    return value ? "true" : "false";
}

bool RegexFindString(const std::string &line, const std::string &key, std::string *out) {
    const std::regex pattern("\"" + key + "\"\\s*:\\s*\"([^\"]+)\"");
    std::smatch match;
    if (!std::regex_search(line, match, pattern)) {
        return false;
    }
    *out = match[1].str();
    return true;
}

bool RegexFindInt(const std::string &line, const std::string &key, int *out) {
    const std::regex pattern("\"" + key + "\"\\s*:\\s*(-?[0-9]+)");
    std::smatch match;
    if (!std::regex_search(line, match, pattern)) {
        return false;
    }
    *out = ParseInt(match[1].str(), key);
    return true;
}

bool RegexFindDouble(const std::string &line, const std::string &key, double *out) {
    const std::regex pattern(
        "\"" + key + "\"\\s*:\\s*(-?[0-9]+(?:\\.[0-9]+)?(?:[eE][-+]?[0-9]+)?)");
    std::smatch match;
    if (!std::regex_search(line, match, pattern)) {
        return false;
    }
    *out = ParseDouble(match[1].str(), key);
    return true;
}

Command ParseCommand(const std::string &line) {
    Command command;
    if (line.empty()) {
        throw std::runtime_error("empty command");
    }

    if (line[0] == '{') {
        if (!RegexFindString(line, "type", &command.type)) {
            throw std::runtime_error("missing type");
        }
        if (command.type == "move") {
            if (!RegexFindInt(line, "seq", &command.seq)) {
                throw std::runtime_error("missing seq");
            }
            RegexFindDouble(line, "vx", &command.vx);
            RegexFindDouble(line, "vy", &command.vy);
            RegexFindDouble(line, "yaw", &command.yaw);
        } else if (command.type == "stop") {
            RegexFindInt(line, "seq", &command.seq);
        }
        return command;
    }

    std::istringstream stream(line);
    stream >> command.type;
    std::transform(command.type.begin(), command.type.end(), command.type.begin(), ::tolower);
    if (command.type == "move") {
        stream >> command.seq >> command.vx >> command.vy >> command.yaw;
        if (!stream) {
            throw std::runtime_error("MOVE requires seq vx vy yaw");
        }
    } else if (command.type == "stop") {
        stream >> command.seq;
        if (!stream) {
            throw std::runtime_error("STOP requires seq");
        }
    }
    return command;
}

bool SendLine(int fd, const std::string &line) {
    const std::string data = line + "\n";
    const char *ptr = data.c_str();
    std::size_t remaining = data.size();
    while (remaining > 0) {
        const ssize_t sent = ::send(fd, ptr, remaining, 0);
        if (sent <= 0) {
            return false;
        }
        ptr += sent;
        remaining -= static_cast<std::size_t>(sent);
    }
    return true;
}

bool RecvLine(int fd, std::string *line) {
    line->clear();
    char ch = '\0';
    while (true) {
        const ssize_t received = ::recv(fd, &ch, 1, 0);
        if (received == 0) {
            return false;
        }
        if (received < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        if (ch == '\n') {
            return true;
        }
        if (ch != '\r') {
            line->push_back(ch);
        }
    }
}

class MotionDaemon {
public:
    explicit MotionDaemon(Options options)
        : options_(std::move(options)) {}

    int Run() {
        PrintConfig();
        if (options_.enable_real_move) {
            InitSdk();
        } else {
            std::cout << "[MOTION_DAEMON][DRYRUN] SDK2 not initialized\n";
        }
        CreateServerSocket();
        watchdog_thread_ = std::thread(&MotionDaemon::WatchdogLoop, this);
        std::cout << "[MOTION_DAEMON] listening\n";

        while (!g_shutdown_requested.load()) {
            sockaddr_un client_addr {};
            socklen_t client_len = sizeof(client_addr);
            const int client_fd = ::accept(server_fd_, reinterpret_cast<sockaddr *>(&client_addr), &client_len);
            if (client_fd < 0) {
                if (errno == EINTR) {
                    continue;
                }
                if (!g_shutdown_requested.load()) {
                    std::cerr << "[MOTION_DAEMON][ERROR] accept failed: " << std::strerror(errno) << "\n";
                }
                continue;
            }
            HandleClient(client_fd);
        }
        Shutdown();
        return 0;
    }

private:
    void PrintConfig() {
        std::cout << "[MOTION_DAEMON] starting\n";
        std::cout << "[MOTION_DAEMON] iface=" << options_.iface << "\n";
        std::cout << "[MOTION_DAEMON] socket=" << options_.socket_path << "\n";
        std::cout << "[MOTION_DAEMON] watchdog_ms=" << options_.watchdog_ms << "\n";
        std::cout << "[MOTION_DAEMON] max_vx=" << options_.max_vx << "\n";
        std::cout << "[MOTION_DAEMON] max_vy=" << options_.max_vy << "\n";
        std::cout << "[MOTION_DAEMON] max_yaw=" << options_.max_yaw << "\n";
        std::cout << "[MOTION_DAEMON] real_move_enabled=" << JsonBool(options_.enable_real_move) << "\n";
    }

    void InitSdk() {
        unitree::robot::ChannelFactory::Instance()->Init(0, options_.iface.c_str());
        sport_client_ = std::make_unique<unitree::robot::go2::SportClient>();
        sport_client_->SetTimeout(10.0f);
        sport_client_->Init();
        std::cout << "[MOTION_DAEMON] SDK2 initialized\n";
        PrepareRealMoveMode();
    }

    void PrepareRealMoveMode() {
        if (!sport_client_) {
            throw std::runtime_error("SportClient is not initialized");
        }
        std::cout << "[MOTION_DAEMON][REAL] SwitchJoystick(false)\n";
        std::cout << "[MOTION_DAEMON][REAL] SwitchJoystick(false) ret="
                  << sport_client_->SwitchJoystick(false) << "\n";
        joystick_disabled_ = true;
        std::this_thread::sleep_for(std::chrono::milliseconds(500));

        std::cout << "[MOTION_DAEMON][REAL] StandUp ret="
                  << sport_client_->StandUp() << "\n";
        std::this_thread::sleep_for(std::chrono::seconds(3));

        std::cout << "[MOTION_DAEMON][REAL] BalanceStand ret="
                  << sport_client_->BalanceStand() << "\n";
        std::this_thread::sleep_for(std::chrono::seconds(2));

        std::cout << "[MOTION_DAEMON][REAL] SpeedLevel(1) ret="
                  << sport_client_->SpeedLevel(1) << "\n";
        std::this_thread::sleep_for(std::chrono::milliseconds(500));

        std::cout << "[MOTION_DAEMON][REAL] ClassicWalk(true) ret="
                  << sport_client_->ClassicWalk(true) << "\n";
        classic_walk_enabled_ = true;
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    void CreateServerSocket() {
        ::unlink(options_.socket_path.c_str());
        server_fd_ = ::socket(AF_UNIX, SOCK_STREAM, 0);
        if (server_fd_ < 0) {
            throw std::runtime_error("socket failed");
        }

        sockaddr_un addr {};
        addr.sun_family = AF_UNIX;
        if (options_.socket_path.size() >= sizeof(addr.sun_path)) {
            throw std::runtime_error("socket path too long");
        }
        std::strncpy(addr.sun_path, options_.socket_path.c_str(), sizeof(addr.sun_path) - 1);

        if (::bind(server_fd_, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0) {
            throw std::runtime_error(std::string("bind failed: ") + std::strerror(errno));
        }
        if (::listen(server_fd_, 1) != 0) {
            throw std::runtime_error(std::string("listen failed: ") + std::strerror(errno));
        }
    }

    void HandleClient(int client_fd) {
        std::cout << "[MOTION_DAEMON] client connected\n";
        std::string line;
        while (!g_shutdown_requested.load() && RecvLine(client_fd, &line)) {
            try {
                const Command command = ParseCommand(line);
                if (command.type == "ping") {
                    SendLine(client_fd, "{\"type\":\"pong\"}");
                } else if (command.type == "status") {
                    SendLine(client_fd, MakeStatus());
                } else if (command.type == "move") {
                    HandleMove(client_fd, command);
                } else if (command.type == "stop") {
                    HandleStop(client_fd, command.seq);
                } else {
                    SendLine(client_fd, "{\"type\":\"error\",\"error\":\"unsupported command\"}");
                }
            } catch (const std::exception &exc) {
                SendLine(client_fd, std::string("{\"type\":\"error\",\"error\":\"") + exc.what() + "\"}");
                if (IsMoving()) {
                    SafeStopMove();
                    MarkStopped();
                }
            }
        }
        ::close(client_fd);
        std::cout << "[MOTION_DAEMON] client disconnected, StopMove\n";
        SafeStopMove();
        MarkStopped();
    }

    void HandleMove(int client_fd, const Command &command) {
        std::lock_guard<std::mutex> lock(state_mutex_);
        if (command.seq <= last_seq_) {
            SendLine(client_fd, "{\"type\":\"move_ack\",\"accepted\":false,\"error\":\"stale seq\"}");
            return;
        }
        last_seq_ = command.seq;
        double vx = std::max(-options_.max_vx, std::min(options_.max_vx, command.vx));
        double vy = 0.0;
        double yaw = std::max(-options_.max_yaw, std::min(options_.max_yaw, command.yaw));
        if (options_.max_vy == 0.0) {
            vy = 0.0;
        }

        last_command_time_ = std::chrono::steady_clock::now();
        moving_ = std::abs(vx) > 1e-6 || std::abs(vy) > 1e-6 || std::abs(yaw) > 1e-6;
        watchdog_fired_ = false;

        if (options_.enable_real_move) {
            if (!sport_client_) {
                throw std::runtime_error("SportClient is not initialized");
            }
            sport_client_->Move(static_cast<float>(vx), static_cast<float>(vy), static_cast<float>(yaw));
        } else {
            std::cout << "[MOTION_DAEMON][DRYRUN] move seq=" << command.seq
                      << " vx=" << vx << " vy=" << vy << " yaw=" << yaw << "\n";
        }

        SendLine(
            client_fd,
            "{\"type\":\"move_ack\",\"seq\":" + std::to_string(command.seq) +
                ",\"accepted\":true,\"real_move\":" + JsonBool(options_.enable_real_move) + "}");
    }

    void HandleStop(int client_fd, int seq) {
        {
            std::lock_guard<std::mutex> lock(state_mutex_);
            if (seq > last_seq_) {
                last_seq_ = seq;
            }
        }
        std::cout << "[MOTION_DAEMON] stop seq=" << seq << "\n";
        SafeStopMove();
        MarkStopped();
        SendLine(client_fd, "{\"type\":\"stop_ack\",\"seq\":" + std::to_string(seq) + "}");
    }

    std::string MakeStatus() {
        std::lock_guard<std::mutex> lock(state_mutex_);
        long age_ms = -1;
        if (last_command_time_.time_since_epoch().count() != 0) {
            age_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - last_command_time_).count();
        }
        return "{\"type\":\"status\",\"connected\":true,\"real_move_enabled\":" +
               JsonBool(options_.enable_real_move) + ",\"last_seq\":" +
               std::to_string(last_seq_) + ",\"last_command_age_ms\":" +
               std::to_string(age_ms) + ",\"watchdog_ms\":" +
               std::to_string(options_.watchdog_ms) + "}";
    }

    void WatchdogLoop() {
        while (!g_shutdown_requested.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            bool should_stop = false;
            {
                std::lock_guard<std::mutex> lock(state_mutex_);
                if (moving_ && !watchdog_fired_) {
                    const auto age_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::steady_clock::now() - last_command_time_).count();
                    should_stop = age_ms > options_.watchdog_ms;
                    if (should_stop) {
                        watchdog_fired_ = true;
                        moving_ = false;
                    }
                }
            }
            if (should_stop) {
                std::cout << "[MOTION_DAEMON][WATCHDOG] command timeout, StopMove\n";
                SafeStopMove();
            }
        }
    }

    bool IsMoving() {
        std::lock_guard<std::mutex> lock(state_mutex_);
        return moving_;
    }

    void MarkStopped() {
        std::lock_guard<std::mutex> lock(state_mutex_);
        moving_ = false;
        watchdog_fired_ = false;
        last_command_time_ = std::chrono::steady_clock::time_point();
    }

    void SafeStopMove() {
        if (!options_.enable_real_move) {
            std::cout << "[MOTION_DAEMON][DRYRUN] StopMove skipped\n";
            return;
        }
        if (!sport_client_) {
            std::cerr << "[MOTION_DAEMON][ERROR] StopMove skipped: SportClient is not initialized\n";
            return;
        }
        try {
            sport_client_->StopMove();
        } catch (const std::exception &exc) {
            std::cerr << "[MOTION_DAEMON][ERROR] StopMove failed: " << exc.what() << "\n";
        } catch (...) {
            std::cerr << "[MOTION_DAEMON][ERROR] StopMove failed\n";
        }
    }

    void RestoreRealMoveMode() {
        if (!options_.enable_real_move || !sport_client_) {
            return;
        }
        try {
            if (classic_walk_enabled_) {
                std::cout << "[MOTION_DAEMON][REAL] ClassicWalk(false)\n";
                std::cout << "[MOTION_DAEMON][REAL] ClassicWalk(false) ret="
                          << sport_client_->ClassicWalk(false) << "\n";
                classic_walk_enabled_ = false;
            }
            if (joystick_disabled_) {
                std::cout << "[MOTION_DAEMON][REAL] SwitchJoystick(true)\n";
                std::cout << "[MOTION_DAEMON][REAL] SwitchJoystick(true) ret="
                          << sport_client_->SwitchJoystick(true) << "\n";
                joystick_disabled_ = false;
            }
        } catch (const std::exception &exc) {
            std::cerr << "[MOTION_DAEMON][ERROR] real mode restore failed: "
                      << exc.what() << "\n";
        } catch (...) {
            std::cerr << "[MOTION_DAEMON][ERROR] real mode restore failed\n";
        }
    }

    void Shutdown() {
        std::cout << "[MOTION_DAEMON] shutting down, StopMove\n";
        SafeStopMove();
        RestoreRealMoveMode();
        MarkStopped();
        if (watchdog_thread_.joinable()) {
            watchdog_thread_.join();
        }
        if (server_fd_ >= 0) {
            ::close(server_fd_);
            server_fd_ = -1;
        }
        ::unlink(options_.socket_path.c_str());
    }

    Options options_;
    int server_fd_ = -1;
    std::unique_ptr<unitree::robot::go2::SportClient> sport_client_;
    std::thread watchdog_thread_;
    std::mutex state_mutex_;
    int last_seq_ = 0;
    bool moving_ = false;
    bool watchdog_fired_ = false;
    bool joystick_disabled_ = false;
    bool classic_walk_enabled_ = false;
    std::chrono::steady_clock::time_point last_command_time_;
};

}  // namespace

int main(int argc, char **argv) {
    std::cout.setf(std::ios::unitbuf);
    std::cerr.setf(std::ios::unitbuf);
    std::signal(SIGINT, SignalHandler);
    std::signal(SIGTERM, SignalHandler);
    try {
        Options options = ParseArgs(argc, argv);
        ValidateRealMoveGuards(options);
        MotionDaemon daemon(options);
        return daemon.Run();
    } catch (const std::exception &exc) {
        std::cerr << "[MOTION_DAEMON][ERROR] " << exc.what() << "\n";
        return 1;
    }
}
