import Foundation

// Resolves the bundled pieces inside MusicTools.app/Contents/Resources:
//
//   Resources/server/   <- your music-tools repo: server.js, index.html,
//                          login.html, public/, the scripts, vendor/, pylibs/,
//                          node_modules/  (copied in by build_app.sh)
//
// server.js finds its own scripts/vendor/pylibs relative to __dirname, so the
// Swift side only needs to launch `node server.js` and point the web view at it.
//
// Dev override (iterate on server.js without rebuilding the .app):
//   MUSIC_TOOLS_SERVER_DIR=/abs/path/to/your/music-tools  swift run
struct BundlePaths {

    let resourcesDir: URL

    init() {
        if let res = Bundle.main.resourceURL {
            resourcesDir = res
        } else {
            resourcesDir = Bundle.main.bundleURL.deletingLastPathComponent()
        }
    }

    /// Where server.js lives. Overridable for dev so you can run straight
    /// against your repo (with its node_modules) before bundling.
    var serverDir: URL {
        if let dev = ProcessInfo.processInfo.environment["MUSIC_TOOLS_SERVER_DIR"] {
            return URL(fileURLWithPath: dev, isDirectory: true)
        }
        return resourcesDir.appendingPathComponent("server", isDirectory: true)
    }

    var serverEntry: URL { serverDir.appendingPathComponent("server.js") }

    /// Node interpreter: a vendored binary if you ship one, else system node.
    /// Returns the executable plus any leading args (so `/usr/bin/env node`
    /// works when relying on the system install).
    var node: (url: URL, leadingArgs: [String]) {
        let vendored = serverDir.appendingPathComponent("vendor/node/bin/node")
        if FileManager.default.isExecutableFile(atPath: vendored.path) {
            return (vendored, [])
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), ["node"])
    }

    /// Log file at ~/Library/Logs/MusicTools/server.log
    var logFile: URL {
        let logs = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MusicTools", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("server.log")
    }
}
