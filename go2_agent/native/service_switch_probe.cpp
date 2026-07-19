#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include <unitree/robot/channel/channel_factory.hpp>
#include <unitree/robot/go2/robot_state/robot_state_client.hpp>

namespace {

struct Options {
    std::string iface = "eth0";
    bool do_switch = false;
    std::string service_name;
    int enable = -1;
};

int ParseInt(const std::string &value, const std::string &name) {
    char *end = nullptr;
    const long parsed = std::strtol(value.c_str(), &end, 10);
    if (end == value.c_str() || *end != '\0') {
        throw std::runtime_error("invalid integer value for " + name + ": " + value);
    }
    return static_cast<int>(parsed);
}

void PrintHelp(const char *program) {
    std::cout
        << "Usage:\n"
        << "  " << program << " [--iface eth0]\n"
        << "  " << program << " [--iface eth0] --switch <service> --enable <0|1>\n"
        << "\n"
        << "Examples:\n"
        << "  " << program << " --iface eth0\n"
        << "  " << program << " --iface eth0 --switch mcf --enable 1\n"
        << "  " << program << " --iface eth0 --switch sport_mode --enable 1\n"
        << "\n"
        << "Safety:\n"
        << "  Default mode is read-only ServiceList.\n"
        << "  This probe never calls SportClient, Move, StandUp, or StopMove.\n";
}

Options ParseArgs(int argc, char **argv) {
    Options options;
    for (int i = 1; i < argc; ++i) {
        const std::string arg(argv[i]);
        if (arg == "--help" || arg == "-h") {
            PrintHelp(argv[0]);
            std::exit(0);
        } else if (arg == "--iface") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--iface requires a value");
            }
            options.iface = argv[++i];
        } else if (arg == "--switch") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--switch requires a value");
            }
            options.do_switch = true;
            options.service_name = argv[++i];
        } else if (arg == "--enable") {
            if (i + 1 >= argc) {
                throw std::runtime_error("--enable requires 0 or 1");
            }
            options.enable = ParseInt(argv[++i], "--enable");
            if (options.enable != 0 && options.enable != 1) {
                throw std::runtime_error("--enable must be 0 or 1");
            }
        } else {
            throw std::runtime_error("unknown argument: " + arg);
        }
    }

    if (options.do_switch && options.service_name.empty()) {
        throw std::runtime_error("--switch requires a service name");
    }
    if (options.do_switch && options.enable < 0) {
        throw std::runtime_error("--switch requires --enable <0|1>");
    }
    if (!options.do_switch && options.enable >= 0) {
        throw std::runtime_error("--enable requires --switch <service>");
    }
    return options;
}

void PrintServiceList(unitree::robot::go2::RobotStateClient &client, const std::string &label) {
    std::vector<unitree::robot::go2::ServiceState> services;
    const int32_t ret = client.ServiceList(services);
    std::cout << "[SERVICE_PROBE] ServiceList(" << label << ") ret=" << ret << "\n";
    std::cout << "[SERVICE_PROBE] service_count=" << services.size() << "\n";
    for (const auto &service : services) {
        std::cout << "[SERVICE_PROBE] name=" << service.name
                  << " status=" << service.status
                  << " protect=" << service.protect << "\n";
    }
}

int Run(const Options &options) {
    std::cout.setf(std::ios::unitbuf);
    std::cerr.setf(std::ios::unitbuf);

    std::cout << "[SERVICE_PROBE] iface=" << options.iface << "\n";
    std::cout << "[SERVICE_PROBE] initializing SDK2\n";
    unitree::robot::ChannelFactory::Instance()->Init(0, options.iface.c_str());

    unitree::robot::go2::RobotStateClient client;
    client.SetTimeout(10.0f);
    client.Init();
    std::cout << "[SERVICE_PROBE] SDK2 initialized\n";
    std::cout << "[SERVICE_PROBE] client_api_version=" << client.GetApiVersion() << "\n";
    std::cout << "[SERVICE_PROBE] server_api_version=" << client.GetServerApiVersion() << "\n";

    PrintServiceList(client, "before");

    if (options.do_switch) {
        int32_t status = -1;
        std::cout << "[SERVICE_PROBE] ServiceSwitch name=" << options.service_name
                  << " enable=" << options.enable << "\n";
        const int32_t ret = client.ServiceSwitch(options.service_name, options.enable, status);
        std::cout << "[SERVICE_PROBE] ServiceSwitch ret=" << ret
                  << " status=" << status << "\n";
        PrintServiceList(client, "after");
    }

    unitree::robot::ChannelFactory::Instance()->Release();
    return 0;
}

}  // namespace

int main(int argc, char **argv) {
    try {
        const Options options = ParseArgs(argc, argv);
        return Run(options);
    } catch (const std::exception &exc) {
        std::cerr << "[SERVICE_PROBE][ERROR] " << exc.what() << "\n";
        return 1;
    }
}
