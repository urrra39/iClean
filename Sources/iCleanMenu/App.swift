import Charts
import ICCore
import ICSystem
import SwiftUI

@main
struct ICleanMenuApp: App {
    @StateObject private var model = Model()

    init() {
        // `iCleanMenu --snapshot out.png` renders the menu once (docs and UI checks) and exits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated {
                let view = NSHostingView(rootView: MenuView().environmentObject(Model())
                    .background(Color(nsColor: .windowBackgroundColor)))
                view.frame.size = view.fittingSize
                let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = view
                if args.contains("--light") { window.appearance = NSAppearance(named: .aqua) }
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFrontRegardless()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
                }
            }
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(model)
        } label: {
            Image(systemName: model.icon)
                .accessibilityLabel(Text(model.status.map { String(format: L("a11y.icon"), $0.health.score) } ?? L("daemon.notRunning")))
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = model.status {
                header(s)
                Divider()
                controls(s)
                Divider()
                frozen(s)
            } else {
                Text(L("daemon.notRunning")).font(.headline)
                Button(L("daemon.start")) { model.startDaemon() }
            }
            Divider()
            actions
            if let d = model.detail {
                Divider()
                Text(model.detailTitle).font(.headline)
                ScrollView { Text(d).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    .frame(maxHeight: 220)
                Button(L("close")) { model.detail = nil }
            }
            if let m = model.message {
                Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            }
            Divider()
            permissions
            about
        }
        .padding(14)
        .frame(width: 360)
    }

    func header(_ s: Status) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(format: L("health"), s.health.score)).font(.headline)
                Spacer()
                Text(L("pressure." + s.pressure)).foregroundStyle(s.pressure == "normal" ? Color.secondary : .orange)
            }
            .accessibilityElement(children: .combine)
            if !s.recentPressure.isEmpty {
                Chart(Array(s.recentSwapMB.enumerated()), id: \.offset) { i, mb in
                    LineMark(x: .value("t", i), y: .value("MB", mb))
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 40)
                .accessibilityLabel(Text(String(format: L("a11y.swap"), Int(s.swapUsedMB))))
            }
            Text(String(format: L("forecast"), s.forecast)).font(.caption)
            if !s.focusSafe.isEmpty {
                Text(String(format: L("focusSafe"), s.focusSafe.joined(separator: ", "))).font(.caption).foregroundStyle(.blue)
            }
            // Zero-surprise: the last action is always visible.
            Text(s.lastAction.map { String(format: L("lastAction"), $0) } ?? L("lastAction.none"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if s.frozen.isEmpty && s.pressure == "normal" {
                Text(L("healthyIdle")).font(.caption)
            }
            if let e = s.configError { Text(e).font(.caption).foregroundStyle(.red).lineLimit(3) }
        }
    }

    func controls(_ s: Status) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(L("mode"), selection: Binding(get: { s.mode }, set: { model.setMode($0) })) {
                Text(L("mode.observe")).tag(Mode.observe)
                Text(L("mode.active")).tag(Mode.active)
            }
            .pickerStyle(.segmented)
            Picker(L("profile"), selection: Binding(get: { s.profile }, set: { model.setProfile($0) })) {
                ForEach(["auto", "work", "batterySaver", "presentation", "dev"], id: \.self) { Text(L("profile." + $0)).tag($0) }
            }
        }
    }

    func frozen(_ s: Status) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if s.frozen.isEmpty {
                Text(L("frozen.none")).foregroundStyle(.secondary)
            }
            ForEach(s.frozen, id: \.id) { f in
                HStack {
                    Image(systemName: f.dryRun ? "eye" : "snowflake").accessibilityHidden(true)
                    Text(f.name).lineLimit(1)
                    Spacer()
                    Button(L("thaw")) { model.thaw(f.id) }
                        .accessibilityLabel(Text(String(format: L("a11y.thaw"), f.name)))
                    Button(L("neverFreeze")) { model.neverFreeze(f.id) }
                        .accessibilityLabel(Text(String(format: L("a11y.never"), f.name)))
                }
            }
        }
    }

    var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(L("thawAll")) { model.thawAll() }.keyboardShortcut("t", modifiers: [.command])
                Button(L("undo")) { model.undo() }.keyboardShortcut("z", modifiers: [.command])
            }
            Text(L("hotkey")).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("why")) { model.show("why", title: L("why")) }
                Button(L("digest")) { model.show("stats", title: L("digest")) }
            }
        }
    }

    var permissions: some View {
        HStack {
            Image(systemName: model.accessibility ? "checkmark.shield" : "shield").accessibilityHidden(true)
            Text(model.accessibility ? L("perm.ax.on") : L("perm.ax.off")).font(.caption)
            Spacer()
            if !model.accessibility { Button(L("perm.open")) { model.openAccessibilitySettings() }.font(.caption) }
        }
    }

    var about: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("about.noDelete")).font(.caption).bold().fixedSize(horizontal: false, vertical: true)
            Text(String(format: L("about.version"), icleanVersion) + " · " + L("about.trademark")).font(.caption2).foregroundStyle(.secondary)
            Button(L("quit")) { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
