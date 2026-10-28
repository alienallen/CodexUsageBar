import AppKit
import Foundation
import SwiftUI

struct Window {
    let bucket: String
    let minutes: Int
    let remaining: Int
    let reset: Date?

    var name: String {
        let span: String
        if minutes == 10_080 { span = "7天" }
        else if minutes % 1_440 == 0 { span = "\(minutes / 1_440)天" }
        else if minutes % 60 == 0 { span = "\(minutes / 60)小时" }
        else { span = "\(minutes)分钟" }
        return bucket == "codex" ? span : "\(bucket) \(span)"
    }

    var display: String {
        let when = reset.map { dateFormatter.string(from: $0) } ?? "时间未知"
        return "\(name) \(remaining)% · \(when) 重置"
    }
}

let updateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "HH:mm:ss"
    return f
}()

let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "M/d HH:mm"
    return f
}()

func windows(from result: [String: Any]) throws -> [Window] {
    let buckets: [(String, [String: Any])]
    if let values = result["rateLimitsByLimitId"] as? [String: [String: Any]], !values.isEmpty {
        buckets = values.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    } else if let value = result["rateLimits"] as? [String: Any] {
        buckets = [(value["limitId"] as? String ?? "codex", value)]
    } else {
        throw Failure("没有返回配额数据，请检查 Codex 登录状态。")
    }
    var found: [Window] = []
    for (bucket, value) in buckets {
        for key in ["primary", "secondary"] {
            guard let entry = value[key] as? [String: Any],
                  let percent = entry["usedPercent"] as? NSNumber,
                  let duration = entry["windowDurationMins"] as? NSNumber,
                  duration.intValue > 0, percent.doubleValue.isFinite,
                  percent.doubleValue >= 0, percent.doubleValue <= 100 else { continue }
            let timestamp = (entry["resetsAt"] as? NSNumber)?.doubleValue
            let reset = timestamp.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            found.append(Window(bucket: bucket, minutes: duration.intValue,
                                remaining: Int((100 - percent.doubleValue).rounded(.down)), reset: reset))
        }
    }
    guard !found.isEmpty else { throw Failure("没有可显示的配额窗口。") }
    return found
}

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func codexPath() throws -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let paths = ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
    guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
        throw Failure("找不到 Codex CLI。请安装并登录 Codex。")
    }
    return path
}

func readUsage(executable: String) throws -> [Window] {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["app-server", "--listen", "stdio://"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { throw Failure("无法启动 Codex CLI。") }
    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
    defer {
        timeout.cancel()
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }
    let messages: [[String: Any]] = [
        ["method": "initialize", "id": 1, "params": ["clientInfo": ["name": "codex_usage_menu", "title": "Codex Usage Menu", "version": "1.0"]]],
        ["method": "initialized", "params": [:]],
        ["method": "account/rateLimits/read", "id": 2]
    ]
    for message in messages {
        let data = try JSONSerialization.data(withJSONObject: message)
        try input.fileHandleForWriting.write(contentsOf: data + Data([10]))
    }
    var buffer = Data()
    while true {
        let chunk = output.fileHandleForReading.availableData
        if chunk.isEmpty { break }
        buffer.append(chunk)
        if buffer.count > 1_048_576 { throw Failure("Codex 返回的数据过大。") }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if (object["id"] as? NSNumber)?.intValue == 1, object["error"] != nil {
                throw Failure("Codex 初始化失败，请检查登录状态。")
            }
            guard (object["id"] as? NSNumber)?.intValue == 2 else { continue }
            guard let result = object["result"] as? [String: Any] else {
                throw Failure("无法读取配额，请检查网络及 Codex 登录状态。")
            }
            return try windows(from: result)
        }
    }
    throw Failure("读取超时或 Codex 已退出；请检查网络和登录状态。")
}

final class UsageStore: ObservableObject {
    @Published var windows: [Window] = []
    @Published var loading = false
    @Published var lastUpdate: Date?
    @Published var message: String?

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try readUsage(executable: codexPath()) }
            DispatchQueue.main.async {
                self.loading = false
                switch result {
                case .success(let windows):
                    self.windows = windows
                    self.lastUpdate = Date()
                    self.message = nil
                case .failure(let error):
                    self.message = error.localizedDescription
                }
            }
        }
    }
}

struct PopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct UsagePanel: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme
    private var blue: Color {
        colorScheme == .dark ? Color(red: 0.58, green: 0.80, blue: 1) : Color(red: 0.0, green: 0.30, blue: 0.68)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(blue)
                    .frame(width: 34, height: 34)
                    .background(blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex 用量").font(.system(size: 15, weight: .semibold))
                    Text("账户剩余额度").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { store.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(store.loading)
                .help("立即刷新")
                .accessibilityLabel("立即刷新")
            }
            .padding(.bottom, 16)

            if store.windows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.loading ? "正在读取额度…" : "暂无额度数据")
                        .font(.system(size: 13, weight: .medium))
                    if let message = store.message {
                        Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(store.windows.enumerated()), id: \.offset) { _, window in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(window.name + "额度")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(window.remaining)%")
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(blue)
                                    Text("剩余")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: Double(window.remaining), total: 100)
                                    .progressViewStyle(.linear)
                                    .tint(blue)
                                    .accessibilityLabel("\(window.name)剩余额度")
                                    .accessibilityValue("\(window.remaining)%")
                                HStack(spacing: 5) {
                                    Image(systemName: "clock")
                                    Text(window.reset.map { dateFormatter.string(from: $0) + " 重置" } ?? "重置时间未提供")
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.05)))
                        }
                    }
                }
                .frame(height: min(CGFloat(store.windows.count) * 108, 135))
                if let message = store.message {
                    Label("更新失败，显示上次数据：" + message, systemImage: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }

            Spacer(minLength: 0)
            Divider().padding(.bottom, 11)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.lastUpdate.map { "更新于 " + updateFormatter.string(from: $0) } ?? "等待首次更新")
                        .font(.system(size: 11, weight: .medium))
                    Text("每 60 秒自动更新")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320, height: 315, alignment: .topLeading)
        .background(PopoverMaterial())
    }
}

final class MenuApp: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var timer: Timer?
    private var previewWindow: NSWindow?
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = UsagePanel(store: store)
        if CommandLine.arguments.contains("--preview") {
            let controller = NSHostingController(rootView: panel)
            let window = NSWindow(contentViewController: controller)
            window.title = "Codex Usage 预览"
            if CommandLine.arguments.contains("--light") { window.appearance = NSAppearance(named: .aqua) }
            if CommandLine.arguments.contains("--dark") { window.appearance = NSAppearance(named: .darkAqua) }
            window.styleMask = [.titled, .closable]
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            previewWindow = window
        } else {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            self.item = item
            item.isVisible = true
            if let button = item.button {
                let image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Codex 用量")
                image?.isTemplate = true
                button.image = image
                button.toolTip = "Codex 用量"
                button.target = self
                button.action = #selector(togglePopover(_:))
            }
            popover.behavior = .transient
            popover.appearance = NSApp.effectiveAppearance
            appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
                DispatchQueue.main.async { self?.popover.appearance = app.effectiveAppearance }
            }
            popover.contentViewController = NSHostingController(rootView: panel)
        }
        store.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.store.refresh() }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(sender) }
        else {
            popover.appearance = NSApp.effectiveAppearance
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}

func selfTest() throws {
    let input: [String: Any] = ["rateLimitsByLimitId": ["codex": [
        "primary": ["usedPercent": 32, "windowDurationMins": 10_080, "resetsAt": 1_793_758_831],
        "secondary": NSNull()
    ]]]
    let a = try windows(from: input)
    precondition(a.count == 1 && a[0].remaining == 68 && a[0].name == "7天" && a[0].reset != nil)
    let b = try windows(from: ["rateLimits": ["primary": ["usedPercent": 99.5, "windowDurationMins": 300]]])
    precondition(b.count == 1 && b[0].remaining == 0 && b[0].name == "5小时" && b[0].display.contains("时间未知"))
    do { _ = try windows(from: ["rateLimits": ["primary": NSNull()]]) ; fatalError("missing window accepted") }
    catch is Failure { }
    do { _ = try windows(from: ["rateLimits": ["primary": ["usedPercent": 101, "windowDurationMins": 300]]]); fatalError("invalid percentage accepted") }
    catch is Failure { }
    print("PASS: quota parsing, missing fields, invalid values")
}

if CommandLine.arguments.contains("--self-test") {
    do { try selfTest() } catch { fputs("Self-test failed: \(error)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--check") {
    do { print(try readUsage(executable: codexPath()).map(\.display).joined(separator: " | ")) }
    catch { fputs("读取失败：\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = MenuApp()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
