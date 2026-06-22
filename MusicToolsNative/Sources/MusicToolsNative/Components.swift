import SwiftUI
import AppKit

/// Native folder picker.
func chooseDirectory(start: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose"
    let expanded = (start as NSString).expandingTildeInPath
    if !start.isEmpty, FileManager.default.fileExists(atPath: expanded) {
        panel.directoryURL = URL(fileURLWithPath: expanded)
    }
    return panel.runModal() == .OK ? panel.url?.path : nil
}

struct PathField: View {
    let label: String
    @Binding var text: String
    init(_ label: String, text: Binding<String>) { self.label = label; self._text = text }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("/path/to/folder", text: $text).textFieldStyle(.roundedBorder)
                Button("Browse…") {
                    if let p = chooseDirectory(start: text) { text = p }
                }
            }
        }
    }
}

struct StatusBadge: View {
    @ObservedObject var runner: ToolRunner
    var body: some View {
        Group {
            if runner.isRunning {
                Label("running", systemImage: "circle.dotted").foregroundStyle(Theme.accent)
            } else if let c = runner.exitCode {
                if c == 0 {
                    Label("done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("exit \(c)", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                }
            } else {
                Text("idle").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

struct ConsoleView: View {
    @ObservedObject var runner: ToolRunner
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(runner.lines.enumerated()), id: \.offset) { idx, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.consoleText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(10)
            }
            .background(Theme.consoleBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: runner.lines.count) { _ in
                if let last = runner.lines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .frame(minHeight: 240)
    }
}

/// Shared panel chrome: title + tool-specific controls + run/stop/clear + console.
struct ToolScaffold<Controls: View>: View {
    let title: String
    let subtitle: String
    @ObservedObject var runner: ToolRunner
    let canRun: Bool
    let onRun: () -> Void
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) { controls() }
            HStack(spacing: 10) {
                Button(action: onRun) { Label("Run", systemImage: "play.fill") }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!canRun || runner.isRunning)
                Button(action: runner.cancel) { Label("Stop", systemImage: "stop.fill") }
                    .disabled(!runner.isRunning)
                Button(action: runner.clear) { Label("Clear", systemImage: "trash") }
                    .disabled(runner.isRunning || runner.lines.isEmpty)
                Spacer()
                StatusBadge(runner: runner)
            }
            ConsoleView(runner: runner)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
