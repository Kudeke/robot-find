import SwiftUI
import AVFoundation

@main
struct RobotFindApp: App {
    @StateObject private var connectionManager = SSHConnectionManager()

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIAccessibility.post(notification: .announcement,
                                 argument: "RobotFind. Loading.")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppEntryView()
                .environmentObject(connectionManager)
        }
    }
}
