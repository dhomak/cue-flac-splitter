import SwiftUI

@main
struct MusicToolsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 940, minHeight: 640)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
    }
}

enum Theme {
    static let accent      = Color(red: 0.00, green: 0.91, blue: 0.80) // cyan
    static let pink        = Color(red: 1.00, green: 0.19, blue: 0.55)
    static let consoleBg   = Color(red: 0.03, green: 0.03, blue: 0.06)
    static let consoleText = Color(red: 0.78, green: 0.80, blue: 0.92)
}
