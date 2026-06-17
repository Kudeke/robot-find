#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

#include <unitree/robot/channel/channel_factory.hpp>
#include <unitree/robot/go2/sport/sport_client.hpp>

namespace {

const char *kSdkRoot = "/home/unitree/unitree_sdk/src/04Aug2025_unitree_sdk2";

struct Options {
    bool help = false;
    bool probe = false;
    bool dry_run = false;
    bool stop_only = false;
    bool move = false;
    bool stop = false;
    bool has_iface = false;
    std::string iface;
    double vx = 0.0;
    double vy = 0.0;
    double yaw = 0.0;
};

void PrintHelp(const char *program) {
    std::cout
        << "Usage:\n"
        << "  " << program << " --help\n"
        << "  " << program << " --probe\n"
        << "  " << program << " --dry-run move --vx 0.1 --vy 0.0 --yaw 0.0\n"
        << "  " << program << " --dry-run stop\n"
        << "  " << program << " --stop-only --iface <network_interface>\n"
        << "\n"
        << "Safety:\n"
        << "  This Phase2-E helper does not implement real move.\n"
        << "  Only --stop-only initializes SDK2, and it only calls StopMove().\n";
}

void PrintProbe(int argc, char **argv) {
    std::cout << "[HELPER] executable started\n";
    std::cout << "[HELPER] SDK root path: " << kSdkRoot << "\n";
    std::cout << "[HELPER] expected include path: " << kSdkRoot << "/include\n";
    std::cout << "[HELPER] expected library paths:\n";
    std::cout << "  " << kSdkRoot << "/lib\n";
    std::cout << "  " << kSdkRoot << "/build/lib\n";
    std::cout << "[HELPER] argv:\n";
    for (int i = 0; i < argc; ++i) {
        std::cout << "  argv[" << i << "]=" << argv[i] << "\n";
    }
    std::cout << "[HELPER] safe probe only: SDK2 not initialized\n";
}

double ParseDouble(const std::string &value, const std::string &name) {
    char *end = nullptr;
    const double parsed = std::strtod(value.c_str(), &end);
    if (end == value.c_str() || *end != '\0') {
        throw std::runtime_error("invalid numeric value for " + name + ": " + value);
    }
    return parsed;
}

Options ParseArgs(int argc, char **argv) {
    Options options;
    for (int i = 1; i < argc; ++i) {
        const std::string arg(argv[i]);

        if (arg == "--help") {
            options.help = true;
        } else if (arg == "--probe") {
            options.probe = true;
        } else if (arg == "--dry-run") {
            options.dry_run = true;
        } else if (arg == "--stop-only") {
            options.stop_only = true;
        } else if (arg == "move") {
            options.move = true;
        } else if (arg == "stop") {
            options.stop = true;
        } else if (arg == "--iface") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--iface requires a value");
            }
            options.iface = argv[++i];
            options.has_iface = true;
        } else if (arg == "--vx") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--vx requires a value");
            }
            options.vx = ParseDouble(argv[++i], "--vx");
        } else if (arg == "--vy") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--vy requires a value");
            }
            options.vy = ParseDouble(argv[++i], "--vy");
        } else if (arg == "--yaw") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--yaw requires a value");
            }
            options.yaw = ParseDouble(argv[++i], "--yaw");
        } else {
            throw std::runtime_error("unknown argument: " + arg);
        }
    }
    return options;
}

int RunDryRun(const Options &options) {
    if (options.move) {
        std::cout << "[HELPER][DRYRUN] move vx=" << options.vx
                  << " vy=" << options.vy
                  << " yaw=" << options.yaw << "\n";
        std::cout << "[HELPER][DRYRUN] SDK2 not initialized, robot not controlled\n";
        return 0;
    }

    if (options.stop) {
        std::cout << "[HELPER][DRYRUN] stop\n";
        std::cout << "[HELPER][DRYRUN] SDK2 not initialized, robot not controlled\n";
        return 0;
    }

    std::cerr << "[HELPER][ERROR] --dry-run requires move or stop\n";
    return 2;
}

int RunStopOnly(const Options &options) {
    if (!options.has_iface || options.iface.empty()) {
        std::cerr << "[HELPER][ERROR] --stop-only requires --iface <network_interface>\n";
        return 2;
    }

    if (options.move) {
        std::cerr << "[HELPER][ERROR] real move is disabled in Phase2-E\n";
        return 2;
    }

    std::cout << "[HELPER] stop-only mode\n";
    std::cout << "[HELPER] initializing SDK2 on iface=" << options.iface << "\n";

    unitree::robot::ChannelFactory::Instance()->Init(0, options.iface.c_str());

    unitree::robot::go2::SportClient sport_client;
    sport_client.SetTimeout(10.0f);
    sport_client.Init();

    std::cout << "[HELPER] calling StopMove only\n";
    sport_client.StopMove();
    std::cout << "[HELPER] StopMove complete\n";
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

        if (options.dry_run) {
            return RunDryRun(options);
        }

        if (options.stop_only) {
            return RunStopOnly(options);
        }

        std::cerr << "[HELPER][ERROR] refusing to run without --help, --probe, --dry-run, or --stop-only\n";
        std::cerr << "[HELPER][ERROR] real move is not implemented in Phase2-E\n";
        return 2;
    } catch (const std::exception &exc) {
        std::cerr << "[HELPER][ERROR] " << exc.what() << "\n";
        return 2;
    }
}
