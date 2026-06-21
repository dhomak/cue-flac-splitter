import Foundation
import Darwin

/// Owns the Node server subprocess. It still passes a free PORT (used if your
/// server.js honors it), but it does NOT assume node listens there: it reads
/// the port node prints on startup ("http://localhost:<port>") and health-checks
/// that. So it works whether or not the PORT env change is in place.
final class ServerController {

    private let paths = BundlePaths()
    private var process: Process?
    private var logHandle: FileHandle?

    private var onReady: (() -> Void)?
    private var onFailure: ((String) -> Void)?

    private var didProceed = false
    private var scanText = ""
    private let portRegex = try? NSRegularExpression(
        pattern: "https?://[^\\s/]+?:(\\d{2,5})")

    private(set) var port: UInt16 = 0
    private var preferredPort: UInt16 = 0
    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }

    func start(onReady: @escaping () -> Void,
               onFailure: @escaping (String) -> Void) {
        self.onReady = onReady
        self.onFailure = onFailure

        guard let freePort = Self.findFreePort() else {
            onFailure("Could not allocate a local port.")
            return
        }
        preferredPort = freePort

        guard FileManager.default.fileExists(atPath: paths.serverEntry.path) else {
            onFailure("server.js not found:\n\(paths.serverEntry.path)\n\nCheck that build_app.sh copied your repo into Resources/server (or set MUSIC_TOOLS_SERVER_DIR for dev).")
            return
        }

        let proc = Process()
        let node = paths.node
        proc.executableURL = node.url
        proc.arguments = node.leadingArgs + [paths.serverEntry.path]
        proc.currentDirectoryURL = paths.serverDir

        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "")
        env["PORT"] = String(freePort)
        if let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first,
           FileManager.default.fileExists(atPath: music.path) {
            env["MUSIC_ROOT"] = music.path
        }
        env["NODE_ENV"] = "production"
        proc.environment = env

        // --- stdout/stderr: tee to log file AND scan for the port ---------
        FileManager.default.createFile(atPath: paths.logFile.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: paths.logFile)
        logHandle?.seekToEndOfFile()
        logHandle?.write("\n===== MusicTools start \(Date()) (assigned PORT \(freePort)) =====\n".data(using: .utf8)!)

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            self?.logHandle?.write(data)
            self?.scanForPort(data)
        }

        proc.terminationHandler = { p in
            NSLog("MusicTools: node exited with status \(p.terminationStatus)")
        }

        do {
            try proc.run()
        } catch {
            onFailure("Failed to launch node:\n\(error.localizedDescription)\n\nIs Node installed and on PATH? (brew install node)")
            return
        }
        process = proc

        // Fallback: if nothing parseable was printed within 3s, assume the
        // server honored PORT and try the port we assigned.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, !self.didProceed else { return }
            self.proceed(withPort: self.preferredPort)
        }
    }

    func stopAndWait(timeout: TimeInterval = 4) {
        guard let p = process, p.isRunning else { return }
        p.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        try? logHandle?.close()
    }

    // MARK: - Port detection from server output

    private func scanForPort(_ data: Data) {
        guard !didProceed, let chunk = String(data: data, encoding: .utf8) else { return }
        scanText += chunk
        if scanText.count > 4096 { scanText = String(scanText.suffix(2048)) }
        guard let re = portRegex else { return }
        let range = NSRange(scanText.startIndex..., in: scanText)
        if let m = re.firstMatch(in: scanText, range: range),
           let r = Range(m.range(at: 1), in: scanText),
           let p = UInt16(scanText[r]) {
            proceed(withPort: p)
        }
    }

    private func proceed(withPort p: UInt16) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.didProceed else { return }
            self.didProceed = true
            self.port = p
            self.waitForServer(attempts: 40)
        }
    }

    // MARK: - Health check

    private func waitForServer(attempts: Int) {
        var remaining = attempts
        let url = baseURL

        func probe() {
            var req = URLRequest(url: url)
            req.timeoutInterval = 2
            req.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: req) { [weak self] _, response, _ in
                if let http = response as? HTTPURLResponse, http.statusCode < 500 {
                    DispatchQueue.main.async { self?.onReady?() }
                } else {
                    retry()
                }
            }.resume()
        }

        func retry() {
            remaining -= 1
            if remaining <= 0 {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let p = self.process, !p.isRunning {
                        self.onFailure?("Server exited during startup (status \(p.terminationStatus)).\nLog: \(self.paths.logFile.path)")
                    } else {
                        self.onFailure?("Server on port \(self.port) did not answer in time.\nLog: \(self.paths.logFile.path)")
                    }
                }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { probe() }
        }

        probe()
    }

    // MARK: - Free port

    static func findFreePort() -> UInt16? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { return nil }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 { return nil }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        if named != 0 { return nil }

        return UInt16(bigEndian: addr.sin_port)
    }
}
