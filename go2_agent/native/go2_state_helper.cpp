#include <chrono>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <unitree/robot/channel/channel_factory.hpp>
#include <unitree/robot/go2/robot_state/robot_state_client.hpp>

namespace {

const char *kSdkRoot = "/home/unitree/unitree_sdk/src/04Aug2025_unitree_sdk2";

struct Options {
    bool help = false;
    bool probe = false;
    bool read_once = false;
    bool read_loop = false;
    bool verbose = false;
    bool has_iface = false;
    std::string iface;
    int count = 1;
    int interval_ms = 500;
    int report_type = 3;
    int report_freq = 30;
    int warmup_ms = 5000;
};

void PrintHelp(const char *program) {
    std::cout
        << "Usage:\n"
        << "  " << program << " --help\n"
        << "  " << program << " --probe\n"
        << "  " << program << " --read-once --iface wlan0 [--verbose]\n"
        << "  " << program << " --read-loop --iface wlan0 --count 5 --interval-ms 500 [--verbose]\n"
        << "  optional: --report-type 3 --report-freq 30 --warmup-ms 5000\n"
        << "\n"
        << "Safety:\n"
        << "  Phase3-A is read-only.\n"
        << "  This helper does not call Move, StopMove, Stand, Sit, ServiceSwitch, or any motion command.\n";
}

void PrintProbe(int argc, char **argv) {
    std::cout << "[STATE_HELPER] executable started\n";
    std::cout << "[STATE_HELPER] SDK root path: " << kSdkRoot << "\n";
    std::cout << "[STATE_HELPER] expected include path: " << kSdkRoot << "/include\n";
    std::cout << "[STATE_HELPER] expected thirdparty include paths:\n";
    std::cout << "  " << kSdkRoot << "/thirdparty/include\n";
    std::cout << "  " << kSdkRoot << "/thirdparty/include/ddscxx\n";
    std::cout << "[STATE_HELPER] expected library paths:\n";
    std::cout << "  " << kSdkRoot << "/lib/aarch64\n";
    std::cout << "  " << kSdkRoot << "/thirdparty/lib/aarch64\n";
    std::cout << "[STATE_HELPER] argv:\n";
    for (int i = 0; i < argc; ++i) {
        std::cout << "  argv[" << i << "]=" << argv[i] << "\n";
    }
    std::cout << "[STATE_HELPER] safe probe only: SDK2 not initialized\n";
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

        if (arg == "--help") {
            options.help = true;
        } else if (arg == "--probe") {
            options.probe = true;
        } else if (arg == "--read-once") {
            options.read_once = true;
        } else if (arg == "--read-loop") {
            options.read_loop = true;
        } else if (arg == "--verbose") {
            options.verbose = true;
        } else if (arg == "--iface") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--iface requires a value");
            }
            options.iface = argv[++i];
            options.has_iface = true;
        } else if (arg == "--count") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--count requires a value");
            }
            options.count = ParseInt(argv[++i], "--count");
        } else if (arg == "--interval-ms") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--interval-ms requires a value");
            }
            options.interval_ms = ParseInt(argv[++i], "--interval-ms");
        } else if (arg == "--report-type") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--report-type requires a value");
            }
            options.report_type = ParseInt(argv[++i], "--report-type");
        } else if (arg == "--report-freq") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--report-freq requires a value");
            }
            options.report_freq = ParseInt(argv[++i], "--report-freq");
        } else if (arg == "--warmup-ms") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--warmup-ms requires a value");
            }
            options.warmup_ms = ParseInt(argv[++i], "--warmup-ms");
        } else {
            throw std::runtime_error("unknown argument: " + arg);
        }
    }
    return options;
}

void ValidateReadOptions(const Options &options) {
    if (!options.has_iface || options.iface.empty()) {
        throw std::runtime_error("read mode requires --iface <network_interface>");
    }
    if (options.count <= 0) {
        throw std::runtime_error("--count must be greater than 0");
    }
    if (options.interval_ms < 0) {
        throw std::runtime_error("--interval-ms must be >= 0");
    }
    if (options.report_freq <= 0) {
        throw std::runtime_error("--report-freq must be greater than 0");
    }
    if (options.warmup_ms < 0) {
        throw std::runtime_error("--warmup-ms must be >= 0");
    }
}

template <typename Callable>
int TimedSdkCall(const std::string &name, bool verbose, Callable callable) {
    if (verbose) {
        std::cout << "[STATE_HELPER][VERBOSE] calling " << name << "\n";
    }
    const auto start = std::chrono::steady_clock::now();
    const int ret = callable();
    const auto end = std::chrono::steady_clock::now();
    const auto cost_us = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();
    std::cout << "[STATE_HELPER] " << name << " ret=" << ret << " cost_us=" << cost_us << "\n";
    return ret;
}

void PrintServiceStates(const std::vector<unitree::robot::go2::ServiceState> &states) {
    std::cout << "[STATE_HELPER] service_state_count=" << states.size() << "\n";
    for (std::size_t i = 0; i < states.size(); ++i) {
        const auto &state = states[i];
        std::cout << "[STATE_HELPER] service_state[" << i << "]"
                  << " name=" << state.name
                  << " status=" << state.status
                  << " protect=" << state.protect
                  << "\n";
    }
}

int ReadOnce(unitree::robot::go2::RobotStateClient &client, int index, bool verbose) {
    std::vector<unitree::robot::go2::ServiceState> service_states;
    const int ret = TimedSdkCall(
        "RobotStateClient::ServiceList",
        verbose,
        [&client, &service_states]() {
            return client.ServiceList(service_states);
        });

    std::cout << "[STATE_HELPER] read_index=" << index << "\n";
    if (ret != 0) {
        std::cout << "[STATE_HELPER] ServiceList returned non-zero ret; exiting read safely\n";
    }
    PrintServiceStates(service_states);
    std::cout << "[STATE_HELPER] battery_or_power=not_available_from_ServiceList\n";
    std::cout << "[STATE_HELPER] mode_or_state=see_service_state_entries\n";
    std::cout << "[STATE_HELPER] error_code=not_available_from_ServiceList\n";
    std::cout << "[STATE_HELPER] temperature=not_available_from_ServiceList\n";

    return ret;
}

int RunRead(const Options &options) {
    ValidateReadOptions(options);

    const int iterations = options.read_once ? 1 : options.count;

    std::cout << "[STATE_HELPER] read-only mode\n";
    std::cout << "[STATE_HELPER] initializing SDK2 on iface=" << options.iface << "\n";
    std::cout << "[STATE_HELPER] no motion commands will be called\n";
    std::cout << "[STATE_HELPER] report_type=" << options.report_type
              << " report_freq=" << options.report_freq
              << " warmup_ms=" << options.warmup_ms << "\n";

    if (options.verbose) {
        std::cout << "[STATE_HELPER][VERBOSE] calling ChannelFactory::Instance()->Init(0, iface)\n";
    }
    unitree::robot::ChannelFactory::Instance()->Init(0, options.iface.c_str());

    unitree::robot::go2::RobotStateClient robot_state_client;
    if (options.verbose) {
        std::cout << "[STATE_HELPER][VERBOSE] calling RobotStateClient::SetTimeout(10.0f)\n";
    }
    robot_state_client.SetTimeout(10.0f);
    if (options.verbose) {
        std::cout << "[STATE_HELPER][VERBOSE] calling RobotStateClient::Init()\n";
    }
    robot_state_client.Init();

    const std::string client_api_version = robot_state_client.GetApiVersion();
    const std::string server_api_version = robot_state_client.GetServerApiVersion();
    std::cout << "[STATE_HELPER] client_api_version=" << client_api_version << "\n";
    std::cout << "[STATE_HELPER] server_api_version=" << server_api_version << "\n";
    if (client_api_version != server_api_version) {
        std::cout << "[STATE_HELPER] api_version_mismatch=true\n";
    }

    const int set_report_ret = TimedSdkCall(
        "RobotStateClient::SetReportFreq",
        options.verbose,
        [&robot_state_client, &options]() {
            return robot_state_client.SetReportFreq(options.report_type, options.report_freq);
        });
    if (set_report_ret != 0) {
        std::cout << "[STATE_HELPER] SetReportFreq returned non-zero ret; exiting read safely\n";
        unitree::robot::ChannelFactory::Instance()->Release();
        return 0;
    }

    if (options.warmup_ms > 0) {
        if (options.verbose) {
            std::cout << "[STATE_HELPER][VERBOSE] waiting warmup_ms=" << options.warmup_ms << "\n";
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(options.warmup_ms));
    }

    int last_ret = 0;
    for (int i = 0; i < iterations; ++i) {
        last_ret = ReadOnce(robot_state_client, i, options.verbose);
        if (last_ret != 0) {
            unitree::robot::ChannelFactory::Instance()->Release();
            return 0;
        }
        if (i + 1 < iterations && options.interval_ms > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(options.interval_ms));
        }
    }

    unitree::robot::ChannelFactory::Instance()->Release();
    return 0;
}

}  // namespace

int main(int argc, char **argv) {
    try {
        const Options options = ParseArgs(argc, argv);

        if (options.help) {
            PrintHelp(argv[0]);
            return 0;
        }

        if (options.probe) {
            PrintProbe(argc, argv);
            return 0;
        }

        if (options.read_once || options.read_loop) {
            return RunRead(options);
        }

        std::cerr << "[STATE_HELPER][ERROR] refusing to run without --help, --probe, --read-once, or --read-loop\n";
        std::cerr << "[STATE_HELPER][ERROR] Phase3-A is read-only and has no motion commands\n";
        return 2;
    } catch (const std::exception &exc) {
        std::cerr << "[STATE_HELPER][ERROR] " << exc.what() << "\n";
        return 2;
    }
}
