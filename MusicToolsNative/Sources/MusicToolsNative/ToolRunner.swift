import Foundation
import Darwin

/// Runs one script as a subprocess and streams its output. The Swift
/// equivalent of server.js's createJob + SSE, but in-process.
@MainActor
final class ToolRunner: ObservableObject {
    @Published var lines: [String] = []
    @Published var isRunning = false
    @Published var exitCode: Int32?

    private var process: Process?
    private var buffer = ""
    private let maxLines = 5000

    func run(_ cmd: Cmd, onFinish: (() -> Void)? = nil) {
        guard !isRunning else { return }
        lines.removeAll(); buffer = ""; exitCode = nil; isRunning = true

        let proc = Process()
        proc.executableURL = cmd.exe
        proc.arguments = cmd.args
        proc.environment = cmd.env
        if let cwd = cmd.cwd { proc.currentDirectoryURL = cwd }
        // Null stdin: tools like ffmpeg read stdin by default and will hang
        // forever if it's an inherited terminal/pipe with no input.
        proc.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { return }
            let s = String(decoding: d, as: UTF8.self)
            Task { @MainActor [weak self] in self?.ingest(s) }
        }
        proc.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !self.buffer.isEmpty { self.appendLine(self.buffer); self.buffer = "" }
                pipe.fileHandleForReading.readabilityHandler = nil
                self.isRunning = false
                self.exitCode = code
                onFinish?()
            }
        }

        do {
            try proc.run()
        } catch {
            appendLine("[ERROR] \(error.localizedDescription)")
            isRunning = false
        }
        process = proc
    }

    func cancel() { process?.terminate() }

    func clear() { lines.removeAll(); exitCode = nil }

    private func ingest(_ s: String) {
        buffer += s
        let parts = buffer.components(separatedBy: "\n")
        buffer = parts.last ?? ""
        for line in parts.dropLast() { appendLine(line) }
    }

    private func appendLine(_ l: String) {
        let clean = l.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        lines.append(clean)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }
}
