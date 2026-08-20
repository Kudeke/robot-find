import SwiftUI
import AVFoundation

@main
struct RobotFindApp: App {
    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIAccessibility.post(notification: .announcement,
                                 argument: "RobotFind. Loading.")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppEntryView()
        }
    }
}
