import SwiftUI
import AppKit

@main
struct AnyPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            PhoneChassisView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
