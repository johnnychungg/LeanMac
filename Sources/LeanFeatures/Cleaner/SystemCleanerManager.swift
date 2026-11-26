// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin
import AppKit
import SwiftUI
import Combine
import LeanDomain

// MARK: - Models

/// One cleanable item (an app's cache, a log file, a DerivedData project, ...).
public struct JunkItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public var sizeBytes: Int64
    public var isSelected: Bool
    /// Non-nil = must not be cleaned (managed by macOS or the app is running).
    public let lockReason: String?
    /// Soft warning (still selectable): the app is running, the cache will be recreated.
    public var warning: String? = nil
    public var isLocked: Bool { lockReason != nil }
    public var sizeFormatted: String { SystemCleanerManager.formatBytes(sizeBytes) }
}

public struct JunkCategoryItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let icon: String
    public var sizeBytes: Int64
    public var children: [JunkItem]

    public var sizeFormatted: String { SystemCleanerManager.formatBytes(sizeBytes) }
    public var selectableCount: Int { children.filter { !$0.isLocked }.count }
    public var selectedCount: Int { children.filter { $0.isSelected && !$0.isLocked }.count }
    public var selectedBytes: Int64 { children.filter { $0.isSelected && !$0.isLocked }.reduce(0) { $0 + $1.sizeBytes } }

    public var localizedTitle: String {
        switch id {
        case "caches": return tr("App caches")
        case "logs": return tr("Logs & crash reports")
        case "trash": return tr("Trash")
        case "developer": return tr("Xcode DerivedData")
        default: return id
        }
    }
}

public struct LeftoverFileItem: Identifiable, Equatable, Sendable {
    public let id: UUID = UUID()
    public let categoryName: String
    public let url: URL
    public let sizeBytes: Int64
    public var isSelected: Bool

    public var sizeFormatted: String { SystemCleanerManager.formatBytes(sizeBytes) }

    /// The category is already translated when the item is created.
    public var localizedCategoryName: String { categoryName }

    public static func == (lhs: LeftoverFileItem, rhs: LeftoverFileItem) -> Bool {
        lhs.id == rhs.id && lhs.isSelected == rhs.isSelected && lhs.sizeBytes == rhs.sizeBytes
    }
}

public struct InstalledAppItem: Identifiable, Equatable, Sendable {
    public let id: String // Bundle ID or name
    public let name: String
    public let bundleID: String
    public let appURL: URL
    public var appSizeBytes: Int64
    public var leftovers: [LeftoverFileItem] = []
    public var isInspectingLeftovers: Bool = false
    public var leftoversLoaded: Bool = false

    public var leftoverBytes: Int64 { leftovers.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeBytes } }
    public var totalSizeBytes: Int64 { appSizeBytes + leftoverBytes }
    public var totalSizeFormatted: String { SystemCleanerManager.formatBytes(totalSizeBytes) }
    public var appSizeFormatted: String { SystemCleanerManager.formatBytes(appSizeBytes) }

    public static func == (lhs: InstalledAppItem, rhs: InstalledAppItem) -> Bool {
        lhs.id == rhs.id && lhs.appSizeBytes == rhs.appSizeBytes && lhs.leftovers == rhs.leftovers
            && lhs.isInspectingLeftovers == rhs.isInspectingLeftovers
    }
}

public struct LargeFileItem: Identifiable, Equatable, Sendable {
    public let id: UUID = UUID()
    public let name: String
    public let url: URL
    public let sizeBytes: Int64
    public let modificationDate: Date
    public let kind: String

    public var sizeFormatted: String { SystemCleanerManager.formatBytes(sizeBytes) }

    public var folderName: String { url.deletingLastPathComponent().lastPathComponent }

    public var relativeDateFormatted: String {
        let elapsed = Date().timeIntervalSince(modificationDate)
        if elapsed < 86400 { return tr("Today") }
        if elapsed < 86400 * 30 { let d = Int(elapsed / 86400); return tr("\(d)d ago") }
        if elapsed < 86400 * 365 { let m = Int(elapsed / (86400 * 30)); return tr("\(m)mo ago") }
        let y = Int(elapsed / (86400 * 365)); return tr("\(y)y ago")
    }

    public static func == (lhs: LargeFileItem, rhs: LargeFileItem) -> Bool {
        lhs.id == rhs.id && lhs.sizeBytes == rhs.sizeBytes
    }
}

public enum AppSortOrder: Int, Sendable { case size = 0, name = 1 }

// MARK: - System Cleaner Manager

@MainActor
public class SystemCleanerManager: ObservableObject {
    public static let shared = SystemCleanerManager()

    // Sub-tab: 0 Junk, 1 Uninstall apps, 2 Large files
    @Published public var selectedSection: Int = 0

    // 1. Junk cleaning
    @Published public var junkCategories: [JunkCategoryItem] = []
    @Published public var isScanningJunk: Bool = false
    @Published public var isCleaningJunk: Bool = false
    @Published public var hasScannedJunk: Bool = false
    @Published public var cleanedMessage: String? = nil
    @Published public var lastCleanedTimestamp: Date? = nil

    // 2. Uninstall apps
    @Published public var installedApps: [InstalledAppItem] = []
    @Published public var isScanningApps: Bool = false
    @Published public var appSearchQuery: String = ""
    @Published public var appSort: AppSortOrder = .size
    @Published public var selectedAppIDs: Set<String> = []
    @Published public var isUninstalling: Bool = false
    @Published public var uninstallMessage: String? = nil

    // 3. Large files
    @Published public var largeFiles: [LargeFileItem] = []
    @Published public var isScanningLargeFiles: Bool = false
    @Published public var hasScannedLargeFiles: Bool = false
    @Published public var trashingFileIDs: Set<UUID> = []
    @Published public var selectedLargeFileIDs: Set<UUID> = []
    @Published public var largeFileThresholdMB: Int = 200
    @Published public var largeFileMessage: String? = nil

    public var totalJunkBytes: Int64 { junkCategories.reduce(0) { $0 + $1.sizeBytes } }
    public var selectedJunkBytes: Int64 { junkCategories.reduce(0) { $0 + $1.selectedBytes } }
    public var selectedJunkCount: Int { junkCategories.reduce(0) { $0 + $1.selectedCount } }

    public var filteredApps: [InstalledAppItem] {
        let q = appSearchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var list = q.isEmpty ? installedApps : installedApps.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
        switch appSort {
        case .size: list.sort { $0.appSizeBytes > $1.appSizeBytes }
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return list
    }

    public var selectedApps: [InstalledAppItem] { installedApps.filter { selectedAppIDs.contains($0.id) } }
    public var selectedAppsBytes: Int64 { selectedApps.reduce(0) { $0 + $1.totalSizeBytes } }

    public var selectedLargeFiles: [LargeFileItem] { largeFiles.filter { selectedLargeFileIDs.contains($0.id) } }
    public var selectedLargeBytes: Int64 { selectedLargeFiles.reduce(0) { $0 + $1.sizeBytes } }

    private init() {
        junkCategories = ["caches", "logs", "trash", "developer"].map {
            JunkCategoryItem(id: $0, icon: Self.icon(for: $0), sizeBytes: 0, children: [])
        }
    }

    nonisolated private static func icon(for id: String) -> String {
        switch id {
        case "caches": return "internaldrive"
        case "logs": return "doc.text"
        case "trash": return "trash"
        default: return "hammer"
        }
    }

    // MARK: - Utilities

    nonisolated public static func formatBytes(_ bytes: Int64) -> String {
        let b = Double(max(0, bytes))
        if b >= 1024 * 1024 * 1024 { return String(format: "%.2f GB", b / (1024 * 1024 * 1024)) }
        if b >= 1024 * 1024 { return String(format: "%.1f MB", b / (1024 * 1024)) }
        if b >= 1024 { return String(format: "%.0f KB", b / 1024) }
        return "\(bytes) B"
    }

    /// Allocated size (like `du`), walked with fts inside the process, without spawning `du`.
    nonisolated private static func directorySize(at path: String) -> Int64 {
        guard let cpath = strdup(path) else { return 0 }
        defer { free(cpath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cpath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return 0 }
        defer { fts_close(fts) }
        var total: Int64 = 0
        while let entry = fts_read(fts) {
            switch Int32(entry.pointee.fts_info) {
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_D, FTS_DEFAULT:
                if let st = entry.pointee.fts_statp { total += Int64(st.pointee.st_blocks) * 512 }
            default:
                break
            }
        }
        return total
    }

    nonisolated private static func calculateSize(at url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        return directorySize(at: url.path)
    }

    private func confirm(_ title: String, _ message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: tr("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func notify(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
    }

    public func isAppRunning(_ app: InstalledAppItem) -> Bool {
        Self.runningBundleIDs().contains(app.bundleID.lowercased())
    }

    /// Moves to the Trash through Finder; the path is passed via argv so no AppleScript can be injected.
    nonisolated private static func trashViaFinder(_ url: URL) -> Bool {
        let script = "on run argv\n tell application \"Finder\" to delete (POSIX file (item 1 of argv) as alias)\nend run"
        _ = Shell.runner.execute("/usr/bin/osascript", arguments: ["-e", script, url.path], timeout: 60)
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// Moves to the Trash, never deletes permanently.
    nonisolated private static func trash(_ url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            return trashViaFinder(url)
        }
    }

    nonisolated private static func displayName(forBundleID bid: String) -> String? {
        guard bid.contains("."),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - SECTION 1: JUNK CLEANING

    nonisolated private static func getTrashSizeKB() -> Int64 {
        let script = """
        tell application "Finder"
            set totalSize to 0.0
            try
                set sList to size of every item of trash
                repeat with s in sList
                    if contents of s is not missing value then
                        set totalSize to totalSize + (contents of s as real)
                    end if
                end repeat
            end try
            return ((round totalSize) div 1024) as string
        end tell
        """
        let result = Shell.runner.execute("/usr/bin/osascript", arguments: ["-e", script], timeout: 30)
        if result.exitCode == 0,
           let kb = Int64(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) { return max(0, kb) }
        return 0
    }

    nonisolated private static func emptyTrashViaFinder() {
        _ = Shell.runner.execute("/usr/bin/osascript", arguments: ["-e", "tell application \"Finder\" to empty trash"], timeout: 120)
    }

    /// Scans the children of a folder and computes sizes in parallel.
    nonisolated private static func isOwnedByMacOS(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("com.apple.") || lower == "apple"
    }

    nonisolated private static func scanChildren(of dir: URL, categoryID: String, running: Set<String>, previous: Set<String>) -> [JunkItem] {
        let fm = FileManager.default
        guard let all = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        // Folders owned by macOS cannot be cleaned, so they are neither listed nor counted (and not even measured).
        let urls = categoryID == "developer" ? all : all.filter { !isOwnedByMacOS($0.lastPathComponent) }
        var sizes = [Int64](repeating: 0, count: urls.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            let s = autoreleasepool { calculateSize(at: urls[i]) }
            lock.lock(); sizes[i] = s; lock.unlock()
        }
        var items: [JunkItem] = []
        for (i, url) in urls.enumerated() where sizes[i] > 0 { autoreleasepool {
            let raw = url.lastPathComponent
            let lower = raw.lowercased()
            var name = raw
            var lock: String? = nil
            var warn: String? = nil
            if categoryID == "developer" {
                if let dash = raw.lastIndex(of: "-") { name = String(raw[raw.startIndex..<dash]) }
            } else {
                if let app = displayName(forBundleID: raw) { name = app }
                if isOwnedByMacOS(raw) {
                    lock = tr("macOS")      // unreachable after the filter above; kept as a safety net
                } else if !lower.isEmpty, running.contains(where: { lower == $0 || lower.hasPrefix($0 + ".") }) {
                    warn = tr("Running")
                }
            }
            items.append(JunkItem(id: url.path, name: name, url: url, sizeBytes: sizes[i],
                                  isSelected: lock == nil && previous.contains(url.path), lockReason: lock, warning: warn))
        } }
        items.sort { $0.sizeBytes > $1.sizeBytes }
        return items
    }

    public func scanJunk() {
        guard !isScanningJunk else { return }
        isScanningJunk = true
        cleanedMessage = nil

        let previous = Set(junkCategories.flatMap { $0.children.filter { $0.isSelected }.map { $0.id } })
        let running = Self.runningBundleIDs()

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let dirs: [(String, URL)] = [
                ("caches", home.appendingPathComponent("Library/Caches")),
                ("logs", home.appendingPathComponent("Library/Logs")),
                ("trash", home.appendingPathComponent(".Trash")),
                ("developer", home.appendingPathComponent("Library/Developer/Xcode/DerivedData"))
            ]
            var result: [JunkCategoryItem] = []
            for (id, dir) in dirs {
                var children = Self.scanChildren(of: dir, categoryID: id, running: running, previous: previous)
                if id == "trash" {
                    if children.isEmpty {
                        // Cannot be listed (permission) → ask Finder for the total size and clean with "Empty Trash"
                        let kb = Self.getTrashSizeKB()
                        if kb > 0 {
                            children = [JunkItem(id: "trash-all", name: tr("Entire Trash"), url: dir,
                                                 sizeBytes: kb * 1024, isSelected: previous.contains("trash-all"), lockReason: nil)]
                        }
                    }
                }
                result.append(JunkCategoryItem(id: id, icon: Self.icon(for: id),
                                               sizeBytes: children.reduce(0) { $0 + $1.sizeBytes }, children: children))
            }
            DispatchQueue.main.async {
                self.junkCategories = result
                self.isScanningJunk = false
                self.hasScannedJunk = true
                malloc_zone_pressure_relief(nil, 0)
                appLog("🧹 SystemCleaner: Scanned \(Self.formatBytes(result.reduce(0) { $0 + $1.sizeBytes })) of junk.")
            }
        }
    }

    public func toggleJunkItem(category: String, item: String) {
        guard let c = junkCategories.firstIndex(where: { $0.id == category }),
              let i = junkCategories[c].children.firstIndex(where: { $0.id == item }),
              !junkCategories[c].children[i].isLocked else { return }
        junkCategories[c].children[i].isSelected.toggle()
    }

    public func toggleJunkCategory(_ category: String) {
        guard let c = junkCategories.firstIndex(where: { $0.id == category }) else { return }
        let allOn = junkCategories[c].selectedCount == junkCategories[c].selectableCount && junkCategories[c].selectableCount > 0
        for i in junkCategories[c].children.indices where !junkCategories[c].children[i].isLocked {
            junkCategories[c].children[i].isSelected = !allOn
        }
    }

    public func cleanSelectedJunk() {
        guard !isCleaningJunk else { return }
        let selected: [(cat: String, item: JunkItem)] = junkCategories.flatMap { cat in
            cat.children.filter { $0.isSelected && !$0.isLocked }.map { (cat.id, $0) }
        }
        guard !selected.isEmpty else { return }
        let total = selected.reduce(0) { $0 + $1.item.sizeBytes }

        let preview = selected.prefix(10).map { "• \($0.item.name) (\($0.item.sizeFormatted))" }.joined(separator: "\n")
        let more = selected.count > 10 ? "\n" + tr("… and \(selected.count - 10) more items") : ""
        guard confirm(
            tr("Clean \(selected.count) item(s) (\(Self.formatBytes(total)))?"),
            tr("These files are deleted permanently, not moved to the Trash:\n\n\(preview)\(more)"),
            button: tr("Delete")
        ) else { return }

        isCleaningJunk = true
        cleanedMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var freed: Int64 = 0
            for entry in selected {
                if entry.item.id == "trash-all" {
                    Self.emptyTrashViaFinder()
                    freed += entry.item.sizeBytes
                } else if (try? fm.removeItem(at: entry.item.url)) != nil {
                    freed += entry.item.sizeBytes
                }
            }
            NSSound(named: "Glass")?.play()
            DispatchQueue.main.async {
                self.isCleaningJunk = false
                self.lastCleanedTimestamp = Date()
                let freedStr = Self.formatBytes(freed)
                self.cleanedMessage = tr("Cleaned \(freedStr)")
                appLog("✨ SystemCleaner: Cleaned \(freedStr)")
                self.scanJunk()
            }
        }
    }

    // MARK: - SECTION 2: GỠ APP

    public func scanInstalledApps() {
        guard !isScanningApps else { return }
        isScanningApps = true

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let appsDirs = [
                URL(fileURLWithPath: "/Applications"),
                fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            ]
            var urls: [URL] = []
            for dir in appsDirs {
                guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                urls += contents.filter { $0.pathExtension == "app" && !$0.path.hasPrefix("/System/") }
            }

            var sizes = [Int64](repeating: 0, count: urls.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                let s = autoreleasepool { Self.calculateSize(at: urls[i]) }
                lock.lock(); sizes[i] = s; lock.unlock()
            }

            var list: [InstalledAppItem] = []
            for (i, url) in urls.enumerated() {
                let bundle = Bundle(url: url)
                let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let bid = bundle?.bundleIdentifier ?? "unknown.\(url.deletingPathExtension().lastPathComponent)"
                if bid == "com.apple.finder" || bid == "com.apple.Safari" || bid == "com.apple.SystemPreferences" { continue }
                list.append(InstalledAppItem(id: bid, name: name, bundleID: bid, appURL: url, appSizeBytes: sizes[i]))
            }
            list.sort { $0.appSizeBytes > $1.appSizeBytes }

            DispatchQueue.main.async {
                self.installedApps = list
                self.selectedAppIDs = self.selectedAppIDs.filter { id in list.contains { $0.id == id } }
                self.isScanningApps = false
                malloc_zone_pressure_relief(nil, 0)
                appLog("📦 AppUninstaller: Found \(list.count) user applications.")
            }
        }
    }

    public func toggleApp(_ app: InstalledAppItem) {
        if selectedAppIDs.contains(app.id) {
            selectedAppIDs.remove(app.id)
        } else {
            selectedAppIDs.insert(app.id)
            if !app.leftoversLoaded && !app.isInspectingLeftovers { inspectAppLeftovers(for: app) }
        }
    }

    public func toggleLeftover(app: String, leftover: UUID) {
        guard let a = installedApps.firstIndex(where: { $0.id == app }),
              let l = installedApps[a].leftovers.firstIndex(where: { $0.id == leftover }) else { return }
        installedApps[a].leftovers[l].isSelected.toggle()
    }

    public func inspectAppLeftovers(for app: InstalledAppItem) {
        if let idx = installedApps.firstIndex(where: { $0.id == app.id }) {
            installedApps[idx].isInspectingLeftovers = true
        }

        // Bundle IDs of the OTHER installed apps, captured on main: a folder that belongs to a sibling app
        // with a longer ID (Chrome vs Chrome Canary) must never be pre-selected for this app.
        let ownBundleID = app.bundleID.lowercased()
        let otherBundleIDs = installedApps.map { $0.bundleID.lowercased() }
            .filter { $0 != ownBundleID && $0.hasPrefix(ownBundleID) }
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let bid = ownBundleID
            let appName = app.name.lowercased()

            let searchDirs: [(name: String, dir: URL)] = [
                ("Application Support", home.appendingPathComponent("Library/Application Support")),
                (tr("Caches"), home.appendingPathComponent("Library/Caches")),
                (tr("Preferences"), home.appendingPathComponent("Library/Preferences")),
                (tr("Saved State"), home.appendingPathComponent("Library/Saved Application State")),
                ("Containers", home.appendingPathComponent("Library/Containers")),
                ("Group Containers", home.appendingPathComponent("Library/Group Containers")),
                (tr("Logs"), home.appendingPathComponent("Library/Logs")),
                ("WebKit", home.appendingPathComponent("Library/WebKit")),
                ("HTTPStorages", home.appendingPathComponent("Library/HTTPStorages"))
            ]

            var leftovers: [LeftoverFileItem] = []
            let appSubname = app.bundleID.split(separator: ".").last.map(String.init)?.lowercased() ?? appName
            let hasRealBundleID = !bid.hasPrefix("unknown.") && bid.contains(".")
            // A bundle ID match is certain (pre-selected); a name match is a guess (not pre-selected)
            func isStrongMatch(name: String) -> Bool {
                let lower = name.lowercased()
                guard hasRealBundleID, lower.contains(bid) else { return false }
                return !otherBundleIDs.contains { lower.contains($0) }
            }
            func checkMatch(name: String) -> Bool {
                let lower = name.lowercased()
                if isStrongMatch(name: name) { return true }
                if appName.count > 3 && (lower == appName || lower.hasPrefix(appName + ".") || lower.hasPrefix(appName + "-") || lower.hasSuffix("." + appName)) { return true }
                if appSubname.count > 3 && lower == appSubname { return true }
                return false
            }

            for target in searchDirs { autoreleasepool {
                guard let contents = try? fm.contentsOfDirectory(at: target.dir, includingPropertiesForKeys: nil) else { return }
                for url in contents {
                    let last = url.lastPathComponent
                    if checkMatch(name: last) {
                        leftovers.append(LeftoverFileItem(categoryName: target.name, url: url,
                                                          sizeBytes: Self.calculateSize(at: url),
                                                          isSelected: isStrongMatch(name: last)))
                    } else if target.dir.lastPathComponent == "Application Support" || target.dir.lastPathComponent == "Caches" {
                        var isDir: ObjCBool = false
                        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                           let sub = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                            for subUrl in sub where checkMatch(name: subUrl.lastPathComponent) {
                                leftovers.append(LeftoverFileItem(categoryName: "\(target.name)/\(last)", url: subUrl,
                                                                  sizeBytes: Self.calculateSize(at: subUrl),
                                                                  isSelected: isStrongMatch(name: subUrl.lastPathComponent)))
                            }
                        }
                    }
                }
            } }
            leftovers.sort { $0.sizeBytes > $1.sizeBytes }

            DispatchQueue.main.async {
                if let idx = self.installedApps.firstIndex(where: { $0.id == app.id }) {
                    self.installedApps[idx].leftovers = leftovers
                    self.installedApps[idx].isInspectingLeftovers = false
                    self.installedApps[idx].leftoversLoaded = true
                }
                appLog("🔍 Leftovers for \(app.name): \(leftovers.count) item(s) found.")
            }
        }
    }

    public func uninstallSelectedApps() {
        guard !isUninstalling else { return }
        let apps = selectedApps
        guard !apps.isEmpty else { return }

        let running = Self.runningBundleIDs()
        let runningApps = apps.filter { running.contains($0.bundleID.lowercased()) }
        if !runningApps.isEmpty {
            uninstallMessage = tr("Quit first: \(runningApps.map { $0.name }.joined(separator: ", "))")
            return
        }
        if apps.contains(where: { $0.isInspectingLeftovers }) {
            uninstallMessage = tr("Still scanning related files, try again in a moment.")
            return
        }

        let leftoverCount = apps.reduce(0) { $0 + $1.leftovers.filter { $0.isSelected }.count }
        let names = apps.prefix(10).map { "• \($0.name) (\($0.totalSizeFormatted))" }.joined(separator: "\n")
        let more = apps.count > 10 ? "\n" + tr("… and \(apps.count - 10) more apps") : ""
        guard confirm(
            tr("Uninstall \(apps.count) app(s)?"),
            tr("The apps and \(leftoverCount) related item(s) will be moved to the Trash (recoverable):\n\n\(names)\(more)"),
            button: tr("Move to Trash")
        ) else { return }

        isUninstalling = true
        uninstallMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            var freed: Int64 = 0
            var removedIDs: [String] = []
            var failed: [String] = []

            for app in apps {
                for leftover in app.leftovers where leftover.isSelected {
                    if Self.trash(leftover.url) { freed += leftover.sizeBytes }
                }
                if Self.trash(app.appURL) {
                    freed += app.appSizeBytes
                    removedIDs.append(app.id)
                } else {
                    failed.append(app.name)
                    appLog("⚠️ Could not trash app bundle: \(app.appURL.path)")
                }
            }
            NSSound(named: "Trash")?.play()

            DispatchQueue.main.async {
                self.isUninstalling = false
                self.installedApps.removeAll { removedIDs.contains($0.id) }
                self.selectedAppIDs.subtract(removedIDs)
                let freedStr = Self.formatBytes(freed)
                if failed.isEmpty {
                    self.uninstallMessage = tr("Removed \(removedIDs.count) app(s), freed \(freedStr)")
                } else {
                    self.uninstallMessage = tr("Could not remove: \(failed.joined(separator: ", ")) (admin rights needed). Freed \(freedStr).")
                }
                appLog("✨ AppUninstaller: removed \(removedIDs.count), failed \(failed.count)")
            }
        }
    }

    // MARK: - SECTION 3: TỆP LỚN

    public func scanLargeFiles() {
        guard !isScanningLargeFiles else { return }
        isScanningLargeFiles = true
        largeFileMessage = nil

        let thresholdBytes = Int64(largeFileThresholdMB) * 1024 * 1024

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let scanDirs = ["Downloads", "Movies", "Documents", "Desktop"].map { home.appendingPathComponent($0) }

            var found: [LargeFileItem] = []
            for dir in scanDirs {
                guard let enumerator = fm.enumerator(
                    at: dir,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                // One autoreleasepool per iteration: otherwise the temporary URLs/NSDictionaries of hundreds of thousands of files pile up until the block ends
                var more = true
                while more {
                    autoreleasepool {
                        guard let fileURL = enumerator.nextObject() as? URL else { more = false; return }
                        guard let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                              res.isRegularFile == true, let size = res.fileSize, Int64(size) >= thresholdBytes else { return }
                        let ext = fileURL.pathExtension.uppercased()
                        found.append(LargeFileItem(name: fileURL.lastPathComponent, url: fileURL, sizeBytes: Int64(size),
                                                   modificationDate: res.contentModificationDate ?? Date(),
                                                   kind: ext.isEmpty ? "FILE" : ext))
                    }
                }
            }
            found.sort { $0.sizeBytes > $1.sizeBytes }

            DispatchQueue.main.async {
                self.largeFiles = found
                self.selectedLargeFileIDs = []
                self.isScanningLargeFiles = false
                self.hasScannedLargeFiles = true
                malloc_zone_pressure_relief(nil, 0)
                appLog("📂 LargeFiles: Found \(found.count) large files > \(self.largeFileThresholdMB)MB.")
            }
        }
    }

    public func toggleLargeFile(_ id: UUID) {
        if selectedLargeFileIDs.contains(id) { selectedLargeFileIDs.remove(id) } else { selectedLargeFileIDs.insert(id) }
    }

    /// Runs in the background: trashItem/Finder can wait a long time (iCloud files, permission dialogs), so never block the main thread.
    public func trashSelectedLargeFiles() {
        let items = selectedLargeFiles.filter { !trashingFileIDs.contains($0.id) }
        guard !items.isEmpty else { return }

        let names = items.prefix(10).map { "• \($0.name) (\($0.sizeFormatted))" }.joined(separator: "\n")
        let more = items.count > 10 ? "\n" + tr("… and \(items.count - 10) more files") : ""
        guard confirm(
            tr("Move \(items.count) file(s) to the Trash?"),
            tr("Total \(Self.formatBytes(items.reduce(0) { $0 + $1.sizeBytes })), recoverable from the Trash:\n\n\(names)\(more)"),
            button: tr("Move to Trash")
        ) else { return }

        items.forEach { trashingFileIDs.insert($0.id) }
        largeFileMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            var done: [UUID] = []
            var freed: Int64 = 0
            var failed: [String] = []
            for item in items {
                if Self.trash(item.url) {
                    done.append(item.id)
                    freed += item.sizeBytes
                } else {
                    failed.append(item.name)
                    appLog("⚠️ LargeFiles: could not trash \(item.name)")
                }
            }
            NSSound(named: "Pop")?.play()

            DispatchQueue.main.async {
                items.forEach { self.trashingFileIDs.remove($0.id) }
                self.largeFiles.removeAll { done.contains($0.id) }
                self.selectedLargeFileIDs.subtract(done)
                let freedStr = Self.formatBytes(freed)
                self.largeFileMessage = tr("Moved \(done.count) file(s) to the Trash (\(freedStr))")
                if !failed.isEmpty {
                    self.notify(
                        tr("Could not move \(failed.count) file(s)"),
                        tr("macOS denied LeanMac access to these files (folder permission or iCloud). Reveal them in Finder:\n\n\(failed.prefix(8).joined(separator: "\n"))"))
                }
            }
        }
    }

    /// Releases the scan data (very large lists) when it is no longer needed; skipped while a task is running.
    public func releaseData() {
        guard !isScanningJunk, !isCleaningJunk, !isScanningApps, !isUninstalling,
              !isScanningLargeFiles, trashingFileIDs.isEmpty else { return }
        junkCategories = junkCategories.map { JunkCategoryItem(id: $0.id, icon: $0.icon, sizeBytes: 0, children: []) }
        hasScannedJunk = false
        installedApps = []
        selectedAppIDs = []
        largeFiles = []
        selectedLargeFileIDs = []
        hasScannedLargeFiles = false
        IconCache.removeAll()
        malloc_zone_pressure_relief(nil, 0)
    }

    public func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}


// MARK: - Compact icon cache (bounded count, keeps only bitmaps at the displayed size)

enum IconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 120
        return c
    }()

    @MainActor
    static func icon(forFile path: String, points: CGFloat) -> NSImage {
        let key = "\(path)|\(Int(points))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let source = NSWorkspace.shared.icon(forFile: path)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let px = Int(points * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        let image = NSImage(size: NSSize(width: points, height: points))
        if let rep {
            rep.size = NSSize(width: points, height: points)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            source.draw(in: NSRect(x: 0, y: 0, width: points, height: points), from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        } else {
            return source
        }
        cache.setObject(image, forKey: key)
        return image
    }

    static func removeAll() { cache.removeAllObjects() }
}
