// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit
import LeanDomain
import LeanDesignSystem

// MARK: - Background commands (argv, no shell)

private func runTool(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> (out: String, code: Int32) {
    let result = Shell.runner.execute(path, arguments: args, timeout: timeout)
    return (result.output, result.exitCode)
}

// MARK: - 1. Startup items (Launch Agents)

struct StartupRow: Identifiable, Equatable {
    var id: String { info.path }
    let info: LaunchItemInfo
    var disabled: Bool
    var running: Bool
}

@MainActor
final class StartupItemsManager: ObservableObject {
    static let shared = StartupItemsManager()
    @Published private(set) var rows: [StartupRow] = []
    @Published private(set) var isLoading = false
    @Published var showApple = false

    private let uid = getuid()

    func load() {
        guard !isLoading else { return }
        isLoading = true
        let uid = self.uid
        DispatchQueue.global(qos: .userInitiated).async {
            let dirs = [NSHomeDirectory() + "/Library/LaunchAgents", "/Library/LaunchAgents"]
            var infos: [LaunchItemInfo] = []
            for dir in dirs {
                let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
                for f in files where f.hasSuffix(".plist") {
                    let path = dir + "/" + f
                    if let data = FileManager.default.contents(atPath: path),
                       let info = LaunchPlist.parse(data: data, path: path) { infos.append(info) }
                }
            }
            let disabledMap = DisabledDB.parse(runTool("/bin/launchctl", ["print-disabled", "gui/\(uid)"]).out)
            let running = DisabledDB.runningLabels(fromList: runTool("/bin/launchctl", ["list"]).out)
            let rows = infos
                .map { StartupRow(info: $0, disabled: disabledMap[$0.label] ?? false, running: running.contains($0.label)) }
                .sorted { ($0.info.isApple ? 1 : 0, $0.info.displayName.lowercased()) < ($1.info.isApple ? 1 : 0, $1.info.displayName.lowercased()) }
            DispatchQueue.main.async {
                self.rows = rows
                self.isLoading = false
            }
        }
    }

    var visibleRows: [StartupRow] { showApple ? rows : rows.filter { !$0.info.isApple } }
    var appleCount: Int { rows.filter { $0.info.isApple }.count }

    func setEnabled(_ row: StartupRow, _ enabled: Bool) {
        let uid = self.uid
        let target = "gui/\(uid)/\(row.info.label)"
        let path = row.info.path
        if let i = rows.firstIndex(where: { $0.id == row.id }) { rows[i].disabled = !enabled }
        DispatchQueue.global(qos: .userInitiated).async {
            if enabled {
                _ = runTool("/bin/launchctl", ["enable", target])
                _ = runTool("/bin/launchctl", ["bootstrap", "gui/\(uid)", path])
            } else {
                _ = runTool("/bin/launchctl", ["disable", target])
                _ = runTool("/bin/launchctl", ["bootout", target])
            }
            DispatchQueue.main.async { self.isLoading = false; self.load() }
        }
    }
}

// MARK: - 2. Battery / CPU hungry processes

@MainActor
final class EnergyMonitorManager: ObservableObject {
    static let shared = EnergyMonitorManager()
    @Published private(set) var processes: [ProcessEnergy] = []
    @Published private(set) var isLoading = false

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let me = Int(getpid())
        DispatchQueue.global(qos: .utility).async {
            let r = runTool("/usr/bin/top", ["-l", "2", "-s", "1", "-n", "12", "-o", "power", "-stats", "pid,command,cpu,mem,power"], timeout: 12)
            let list = TopParser.parse(r.out, excludingPIDs: [me])
                .filter { $0.command != "top" }
                .prefix(10)
            let result = Array(list)
            DispatchQueue.main.async {
                self.processes = result
                self.isLoading = false
            }
        }
    }

    func runningApp(pid: Int) -> NSRunningApplication? {
        let app = NSRunningApplication(processIdentifier: pid_t(pid))
        return app?.activationPolicy == .regular ? app : nil
    }

    func quit(pid: Int) {
        runningApp(pid: pid)?.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refresh() }
    }
}

private extension ProcessEnergy {
    var command: String { name }
}

// MARK: - 5. Reduced effects mode

@MainActor
final class EffectsManager: ObservableObject {
    static let shared = EffectsManager()
    private let backupKey = "effects_backup_v1"
    @Published private(set) var isOn: Bool
    @Published private(set) var isWorking = false

    init() { isOn = UserDefaults.standard.dictionary(forKey: "effects_backup_v1") != nil }

    func setOn(_ on: Bool) {
        guard !isWorking, on != isOn else { return }
        isWorking = true
        let key = backupKey
        let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        DispatchQueue.global(qos: .userInitiated).async {
            var restartDock = false
            var backup = saved
            for t in EffectsCatalog.tweaks {
                let id = "\(t.domain)|\(t.key)"
                if on {
                    let cur = runTool("/usr/bin/defaults", ["read", t.domain, t.key])
                    backup[id] = cur.code == 0 ? cur.out.trimmingCharacters(in: .whitespacesAndNewlines) : "<absent>"
                    _ = runTool("/usr/bin/defaults", ["write", t.domain, t.key, "-\(t.kind.rawValue)", t.value])
                } else if let orig = backup[id] {
                    if orig == "<absent>" {
                        _ = runTool("/usr/bin/defaults", ["delete", t.domain, t.key])
                    } else {
                        let v = t.kind == .bool ? (orig == "1" || orig == "true" ? "true" : "false") : orig
                        _ = runTool("/usr/bin/defaults", ["write", t.domain, t.key, "-\(t.kind.rawValue)", v])
                    }
                }
                restartDock = restartDock || t.needsDockRestart
            }
            if restartDock { _ = runTool("/usr/bin/killall", ["Dock"]) }
            DispatchQueue.main.async {
                if on { UserDefaults.standard.set(backup, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
                self.isOn = on
                self.isWorking = false
            }
        }
    }
}

// MARK: - Views

struct StartupItemsView: View {
    @ObservedObject private var mgr = StartupItemsManager.shared

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(tr("Startup items (Launch Agents)"))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                JInfoButton(text: tr("Disabling an item stops it now and prevents it from starting at next login. Re-enable any time. Login Items added in System Settings are not listed here."))
                Spacer()
                Button { mgr.load() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(Pal.ink3) }
                    .buttonStyle(.plain)
            }
            if mgr.visibleRows.isEmpty {
                Text(mgr.isLoading ? tr("Scanning...") : tr("No third-party startup items."))
                    .font(.system(size: 12)).foregroundStyle(Pal.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading).jCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(mgr.visibleRows.enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { JDivider() }
                        JToggleRow(icon: row.running ? "bolt.fill" : "bolt",
                                   title: row.info.displayName,
                                   subtitle: row.running ? tr("Running") : (row.disabled ? tr("Disabled") : tr("Runs at login")),
                                   isOn: Binding(get: { !row.disabled }, set: { mgr.setEnabled(row, $0) }))
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 2)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
            }
            if mgr.appleCount > 0 {
                JToggleRow(icon: "apple.logo", title: tr("Show Apple items (\(mgr.appleCount))"),
                           isOn: Binding(get: { mgr.showApple }, set: { mgr.showApple = $0 }))
                    .jCard()
            }
        }
        .onAppear { mgr.load() }
    }
}

struct EnergyView: View {
    @ObservedObject private var mgr = EnergyMonitorManager.shared
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(tr("Top energy consumers"))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                JInfoButton(text: tr("Ranked by macOS Power score (like Activity Monitor). Only regular apps can be quit; system processes are shown for reference."))
                Spacer()
                if mgr.isLoading { ProgressView().controlSize(.small) }
            }
            if mgr.processes.isEmpty {
                Text(tr("Measuring...")).font(.system(size: 12)).foregroundStyle(Pal.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading).jCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(mgr.processes.enumerated()), id: \.element.id) { idx, p in
                        if idx > 0 { JDivider() }
                        row(p).padding(.vertical, 7)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 2)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
            }
        }
        .onAppear {
            mgr.refresh()
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in Task { @MainActor in mgr.refresh() } }
            timer?.tolerance = 2
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func row(_ p: ProcessEnergy) -> some View {
        let app = mgr.runningApp(pid: p.id)
        return HStack(spacing: 10) {
            if let icon = app?.icon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            } else {
                Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(Pal.ink3).frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app?.localizedName ?? p.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink).lineLimit(1)
                Text(String(format: "CPU %.0f%% · RAM %.0f MB · Power %.0f", p.cpu, p.memoryMB, p.power))
                    .font(.system(size: 11)).foregroundStyle(Pal.ink3)
            }
            Spacer(minLength: 6)
            if app != nil {
                Button { mgr.quit(pid: p.id) } label: { Text(tr("Quit")).font(.system(size: 12)) }
                    .buttonStyle(JButtonStyle(kind: .ghost))
            }
        }
    }
}

struct EffectsCard: View {
    @ObservedObject private var mgr = EffectsManager.shared

    var body: some View {
        JToggleRow(icon: "wind", title: tr("Reduce effects (save battery)"),
                   subtitle: mgr.isWorking ? tr("Applying...") : nil,
                   isOn: Binding(get: { mgr.isOn }, set: { mgr.setOn($0) }),
                   trailing: AnyView(JInfoButton(text: tr("Disables window/Dock/Mission Control animations. Dock restarts once. Turning it off restores your previous values."))))
            .jCard()
    }
}
