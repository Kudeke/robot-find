#include <atomic>
#include <chrono>
#include <csignal>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>

#include <unitree/robot/channel/channel_factory.hpp>
#include <unitree/robot/go2/sport/sport_client.hpp>

namespace {

std::atomic<bool> g_stop_requested{false};
std::atomic<bool> g_joystick_disabled{false};
unitree::robot::go2::SportClient *g_client = nullptr;

struct Options {
    std::string iface = "wlan0";
};

void SignalHandler(int) {
    g_stop_requested.store(true);
    if (g_client != nullptr) {
        try {
            std::cerr << "\n[REAL TEST] signal received, StopMove\n";
            g_client->StopMove();
            if (g_joystick_disabled.load()) {
                std::cerr << "[REAL TEST] signal cleanup, SwitchJoystick(true)\n";
                g_client->SwitchJoystick(true);
            }
        } catch (...) {
            std::cerr << "[REAL TEST][ERROR] StopMove failed in signal handler\n";
        }
    }
}

Options ParseArgs(int argc, char **argv) {
    Options options;
    for (int i = 1; i < argc; ++i) {
        const std::string arg(argv[i]);
        if (arg == "--iface") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--iface requires a value");
            }
            options.iface = argv[++i];
        } else if (arg == "--help" || arg == "-h") {
            std::cout << "Usage: " << argv[0] << " [--iface wlan0]\n";
            std::exit(0);
        } else {
            throw std::runtime_error("unknown argument: " + arg);
        }
    }
    return options;
}

bool ConfirmRealMove() {
    std::cout
        << "==================================================\n"
        << "REAL GO2 MOVE TEST\n"
        << "==================================================\n"
        << "\n"
        << "Robot WILL MOVE.\n"
        << "\n"
        << "Expected motion:\n"
        << "\n"
        << "forward\n"
        << "0.05 m/s\n"
        << "1.0 second\n"
        << "\n"
        << "Emergency stop must be available.\n"
        << "\n"
        << "Type:\n"
        << "\n"
        << "YES\n"
        << "\n"
        << "to continue.\n"
        << "\n"
        << "==================================================\n";

    std::string input;
    std::getline(std::cin, input);
    return input == "YES";
}

void StopMoveQuietly(unitree::robot::go2::SportClient &client) {
    try {
        client.StopMove();
    } catch (const std::exception &exc) {
        std::cerr << "[REAL TEST][ERROR] StopMove failed: " << exc.what() << "\n";
    } catch (...) {
        std::cerr << "[REAL TEST][ERROR] StopMove failed\n";
    }
}

void RestoreJoystickQuietly(unitree::robot::go2::SportClient &client) {
    if (!g_joystick_disabled.load()) {
        return;
    }
    try {
        std::cout << "[REAL TEST] SwitchJoystick true\n";
        client.SwitchJoystick(true);
        g_joystick_disabled.store(false);
    } catch (const std::exception &exc) {
        std::cerr << "[REAL TEST][ERROR] SwitchJoystick(true) failed: " << exc.what() << "\n";
    } catch (...) {
        std::cerr << "[REAL TEST][ERROR] SwitchJoystick(true) failed\n";
    }
}

int32_t LogSdkRet(const std::string &name, int32_t ret) {
    std::cout << "[REAL TEST] " << name << " ret=" << ret << "\n";
    return ret;
}

int Run(const Options &options) {
    std::cout.setf(std::ios::unitbuf);
    std::cerr.setf(std::ios::unitbuf);

    unitree::robot::ChannelFactory::Instance()->Init(0, options.iface.c_str());

    unitree::robot::go2::SportClient client;
    g_client = &client;
    client.SetTimeout(10.0f);
    client.Init();

    std::cout << "[REAL TEST] SDK2 initialized\n";

    if (!ConfirmRealMove()) {
        std::cout << "[REAL TEST] cancelled\n";
        StopMoveQuietly(client);
        RestoreJoystickQuietly(client);
        g_client = nullptr;
        return 1;
    }

    if (g_stop_requested.load()) {
        StopMoveQuietly(client);
        RestoreJoystickQuietly(client);
        g_client = nullptr;
        return 130;
    }

    std::cout << "[REAL TEST] SwitchJoystick false\n";
    LogSdkRet("SwitchJoystick(false)", client.SwitchJoystick(false));
    g_joystick_disabled.store(true);
    std::this_thread::sleep_for(std::chrono::milliseconds(500));

    std::cout << "[REAL TEST] StandUp\n";
    LogSdkRet("StandUp", client.StandUp());
    for (int i = 0; i < 30 && !g_stop_requested.load(); ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    if (g_stop_requested.load()) {
        StopMoveQuietly(client);
        RestoreJoystickQuietly(client);
        g_client = nullptr;
        return 130;
    }

    std::cout << "[REAL TEST] BalanceStand\n";
    LogSdkRet("BalanceStand", client.BalanceStand());
    for (int i = 0; i < 20 && !g_stop_requested.load(); ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    if (g_stop_requested.load()) {
        StopMoveQuietly(client);
        RestoreJoystickQuietly(client);
        g_client = nullptr;
        return 130;
    }

    std::cout << "[REAL TEST] SpeedLevel 1\n";
    LogSdkRet("SpeedLevel(1)", client.SpeedLevel(1));
    for (int i = 0; i < 5 && !g_stop_requested.load(); ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    if (g_stop_requested.load()) {
        StopMoveQuietly(client);
        RestoreJoystickQuietly(client);
        g_client = nullptr;
        return 130;
    }

    std::cout << "[REAL TEST] ClassicWalk true\n";
    LogSdkRet("ClassicWalk(true)", client.ClassicWalk(true));
    for (int i = 0; i < 10 && !g_stop_requested.load(); ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    if (g_stop_requested.load()) {
        StopMoveQuietly(client);
        RestoreJoystickQuietly(client);
        g_client = nullptr;
        return 130;
    }

    std::cout << "[REAL TEST] Move\n";
    for (int i = 0; i < 20 && !g_stop_requested.load(); ++i) {
        LogSdkRet("Move", client.Move(0.05f, 0.0f, 0.0f));
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    std::cout << "[REAL TEST] StopMove\n";
    StopMoveQuietly(client);
    std::cout << "[REAL TEST] ClassicWalk false\n";
    LogSdkRet("ClassicWalk(false)", client.ClassicWalk(false));
    RestoreJoystickQuietly(client);
    for (int i = 0; i < 20 && !g_stop_requested.load(); ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    g_client = nullptr;

    std::cout
        << "==================================================\n"
        << "REAL MOVE COMPLETE\n"
        << "==================================================\n";
    return 0;
}

}  // namespace

int main(int argc, char **argv) {
    std::signal(SIGINT, SignalHandler);
    std::signal(SIGTERM, SignalHandler);

    try {
        const Options options = ParseArgs(argc, argv);
        return Run(options);
    } catch (const std::exception &exc) {
        std::cerr << "[REAL TEST][ERROR] " << exc.what() << "\n";
        if (g_client != nullptr) {
            try {
                g_client->StopMove();
                if (g_joystick_disabled.load()) {
                    g_client->SwitchJoystick(true);
                    g_joystick_disabled.store(false);
                }
            } catch (...) {
                std::cerr << "[REAL TEST][ERROR] emergency StopMove failed\n";
            }
        }
        return 1;
    } catch (...) {
        std::cerr << "[REAL TEST][ERROR] unknown exception\n";
        if (g_client != nullptr) {
            try {
                g_client->StopMove();
                if (g_joystick_disabled.load()) {
                    g_client->SwitchJoystick(true);
                    g_joystick_disabled.store(false);
                }
            } catch (...) {
                std::cerr << "[REAL TEST][ERROR] emergency StopMove failed\n";
            }
        }
        return 1;
    }
}
