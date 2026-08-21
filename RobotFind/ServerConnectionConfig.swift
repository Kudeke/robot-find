import Foundation

struct ServerConnectionConfig {
    var host: String
    var sshPort: Int
    var username: String
    var password: String
    var remoteAPIPort: Int

    static let defaultSSHPort = 22
    static let defaultQwenAPIPort = 8000
}

enum SSHConnectionState: Equatable {
    case disconnected
    case connecting
    case authenticating
    case forwarding
    case checkingHealth
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting to SSH..."
        case .authenticating: return "Authenticating..."
        case .forwarding: return "Opening API tunnel..."
        case .checkingHealth: return "Checking Qwen service..."
        case .connected: return "Connected"
        case .failed(let message): return message
        }
    }
}

enum SSHConnectionError: LocalizedError {
    case invalidConfiguration
    case authenticationFailed
    case networkFailure(String)
    case forwardingFailed(String)
    case healthCheckFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Enter a server, username, password, and valid ports."
        case .authenticationFailed:
            return "Authentication failed. Check the username and password."
        case .networkFailure(let message):
            return "Could not reach the server. \(message)"
        case .forwardingFailed(let message):
            return "Could not open the API tunnel. \(message)"
        case .healthCheckFailed(let message):
            return "Qwen API is not reachable through the SSH tunnel. \(message)"
        case .timedOut:
            return "The server connection timed out."
        }
    }
}
