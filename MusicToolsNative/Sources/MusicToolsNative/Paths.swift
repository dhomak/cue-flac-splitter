import Foundation

/// Resolves where the scripts and bundled runtimes live, and builds the
/// command + environment for each — the Swift equivalent of server.js's
/// SCRIPT_DIR / VENDOR_DIR / BUNDLED_PYTHON / SPAWN_ENV.
///
/// Bundle layout (Contents/Resources):
///   scripts/   the 5 scripts
///   pylibs/    vendored pure-python deps (on PYTHONPATH)
///   vendor/python/arm64/bin/python3
///   vendor/bin/arm64/{ffmpeg,ffprobe}
///
/// Dev override: MUSIC_TOOLS_DEV_REPO=/path/to/music-tools  (scripts at its root)
struct Cmd {
    let exe: URL
    let args: [String]
    let env: [String: String]
    let cwd: URL?
}

final class Paths {
    static let shared = Paths()

    let scriptsDir: URL
    let pylibsDir: URL
    let vendorDir: URL

    private init() {
        let env = ProcessInfo.processInfo.environment
        if let repo = env["MUSIC_TOOLS_DEV_REPO"] {
            let r = URL(fileURLWithPath: repo, isDirectory: true)
            scriptsDir = r
            pylibsDir  = r.appendingPathComponent("pylibs")
            vendorDir  = r.appendingPathComponent("vendor")
        } else {
            let res = Bundle.main.resourceURL ?? Bundle.main.bundleURL
            scriptsDir = res.appendingPathComponent("scripts")
            pylibsDir  = res.appendingPathComponent("pylibs")
            vendorDir  = res.appendingPathComponent("vendor")
        }
    }

    private var binDir: URL { vendorDir.appendingPathComponent("bin/arm64") }

    private var vendorPython: URL? {
        let p = vendorDir.appendingPathComponent("python/arm64/bin/python3")
        return FileManager.default.isExecutableFile(atPath: p.path) ? p : nil
    }

    /// Base environment: minimal-PATH-safe (a Finder-launched app gets a sparse
    /// PATH), so prepend the bundled ffmpeg dir + Homebrew + system locations.
    private func baseEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let parts = [binDir.path, "/opt/homebrew/bin", "/opt/homebrew/sbin",
                     "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
                     env["PATH"] ?? ""]
        env["PATH"] = parts.filter { !$0.isEmpty }.joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    func bash(script: String, args: [String]) -> Cmd {
        let p = scriptsDir.appendingPathComponent(script).path
        return Cmd(exe: URL(fileURLWithPath: "/bin/bash"), args: [p] + args,
                   env: baseEnv(), cwd: scriptsDir)
    }

    func perl(script: String, args: [String]) -> Cmd {
        let p = scriptsDir.appendingPathComponent(script).path
        // macOS still ships /usr/bin/perl; fall back to env if it ever moves.
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") {
            return Cmd(exe: URL(fileURLWithPath: "/usr/bin/perl"), args: [p] + args,
                       env: baseEnv(), cwd: scriptsDir)
        }
        return Cmd(exe: URL(fileURLWithPath: "/usr/bin/env"), args: ["perl", p] + args,
                   env: baseEnv(), cwd: scriptsDir)
    }

    func python(script: String, args: [String], extraEnv: [String: String] = [:]) -> Cmd {
        let p = scriptsDir.appendingPathComponent(script).path
        var env = baseEnv()
        env["PYTHONPATH"] = pylibsDir.path
        for (k, v) in extraEnv { env[k] = v }
        if let py = vendorPython {
            return Cmd(exe: py, args: ["-u", p] + args, env: env, cwd: scriptsDir)
        }
        return Cmd(exe: URL(fileURLWithPath: "/usr/bin/env"),
                   args: ["python3", "-u", p] + args, env: env, cwd: scriptsDir)
    }
}
