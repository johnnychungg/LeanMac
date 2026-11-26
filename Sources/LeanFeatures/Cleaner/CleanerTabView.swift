// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit
import LeanDesignSystem
import LeanDomain

// MARK: - Cleaner tab

public struct CleanerTabView: View {
    @ObservedObject var cleanerManager: SystemCleanerManager

    public init(cleanerManager: SystemCleanerManager) {
        self.cleanerManager = cleanerManager
    }

    public var body: some View {
        VStack(spacing: 10) {
            JSegmented(
                items: [tr("Junk"), tr("Uninstall"), tr("Large files")],
                selection: Binding(get: { cleanerManager.selectedSection }, set: { cleanerManager.selectedSection = $0 })
            )
            .padding(.horizontal, 14)

            Group {
                switch cleanerManager.selectedSection {
                case 1: AppUninstallView(manager: cleanerManager)
                case 2: LargeFilesView(manager: cleanerManager)
                default: JunkView(manager: cleanerManager)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.top, 2)
        .onAppear { loadIfNeeded() }
        .onChange(of: cleanerManager.selectedSection) { _, _ in loadIfNeeded() }
    }

    private func loadIfNeeded() {
        switch cleanerManager.selectedSection {
        case 1: if cleanerManager.installedApps.isEmpty { cleanerManager.scanInstalledApps() }
        case 2: if !cleanerManager.hasScannedLargeFiles { cleanerManager.scanLargeFiles() }
        default: if !cleanerManager.hasScannedJunk { cleanerManager.scanJunk() }
        }
    }
}

// MARK: - Shared components

/// Scrolling list + a fixed action bar at the bottom.
private struct ListWithFooter<Content: View, Footer: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) { content() }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
            footer()
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }
}

private struct Spinner: View {
    var body: some View { ProgressView().controlSize(.small).scaleEffect(0.8) }
}

private func emptyState(icon: String, text: String) -> some View {
    VStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Pal.ink3)
        Text(text).font(.system(size: 13)).foregroundStyle(Pal.ink2)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 28)
}

// MARK: - Junk cleaning

private struct JunkView: View {
    @ObservedObject var manager: SystemCleanerManager
    @State private var expanded: Set<String> = []
    @State private var showAll: Set<String> = []

    private let previewCount = 30

    var body: some View {
        ListWithFooter {
            // Overview
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Reclaimable")).font(.system(size: 12)).foregroundStyle(Pal.ink3)
                    Text(SystemCleanerManager.formatBytes(manager.totalJunkBytes))
                        .font(.system(size: 26, weight: .medium)).foregroundStyle(Pal.ink)
                }
                Spacer()
                if manager.isScanningJunk {
                    HStack(spacing: 6) { Spinner(); Text(tr("Scanning")).font(.system(size: 12)).foregroundStyle(Pal.ink3) }
                } else {
                    JChip(text: tr("Rescan"), icon: "arrow.clockwise") { manager.scanJunk() }
                }
            }
            .jCard()

            if let msg = manager.cleanedMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text(msg).font(.system(size: 12))
                    Spacer()
                }
                .foregroundStyle(Pal.ok)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Pal.okBg))
            }

            ForEach(manager.junkCategories) { cat in
                categoryCard(cat)
            }
        } footer: {
            Button { manager.cleanSelectedJunk() } label: {
                if manager.isCleaningJunk {
                    HStack(spacing: 6) { Spinner(); Text(tr("Cleaning…")) }
                } else if manager.selectedJunkCount > 0 {
                    Text(tr("Clean \(manager.selectedJunkCount) item(s) · \(SystemCleanerManager.formatBytes(manager.selectedJunkBytes))"))
                } else {
                    Text(tr("Select items to clean"))
                }
            }
            .buttonStyle(JButtonStyle())
            .disabled(manager.selectedJunkCount == 0 || manager.isCleaningJunk || manager.isScanningJunk)
        }
    }

    private func checkState(_ cat: JunkCategoryItem) -> JCheck.State {
        if cat.selectedCount == 0 { return .off }
        return cat.selectedCount == cat.selectableCount ? .on : .mixed
    }

    @ViewBuilder private func categoryCard(_ cat: JunkCategoryItem) -> some View {
        let isOpen = expanded.contains(cat.id)
        let rows = showAll.contains(cat.id) ? cat.children : Array(cat.children.prefix(previewCount))
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                JCheck(state: checkState(cat), locked: cat.selectableCount == 0) { manager.toggleJunkCategory(cat.id) }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        if isOpen { expanded.remove(cat.id) } else { expanded.insert(cat.id) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        JIcon(name: cat.icon)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cat.localizedTitle).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                            Text(cat.children.isEmpty ? tr("Empty") : tr("\(cat.children.count) items"))
                                .font(.system(size: 12)).foregroundStyle(Pal.ink3)
                        }
                        Spacer(minLength: 4)
                        Text(cat.sizeFormatted).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Pal.ink3)
                            .opacity(cat.children.isEmpty ? 0.3 : 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(cat.children.isEmpty)
            }
            .padding(12)

            if isOpen && !cat.children.isEmpty {
                VStack(spacing: 0) {
                    ForEach(rows) { item in
                        JDivider()
                        HStack(spacing: 10) {
                            JCheck(state: item.isSelected ? .on : .off, locked: item.isLocked) {
                                manager.toggleJunkItem(category: cat.id, item: item.id)
                            }
                            Text(item.name).font(.system(size: 13)).foregroundStyle(item.isLocked ? Pal.ink3 : Pal.ink)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            if let reason = item.lockReason ?? item.warning {
                                JChip(text: reason)
                            }
                            Text(item.sizeFormatted).font(.system(size: 12)).foregroundStyle(Pal.ink2)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                    }
                    if cat.children.count > previewCount && !showAll.contains(cat.id) {
                        JDivider()
                        Button { showAll.insert(cat.id) } label: {
                            Text(tr("Show \(cat.children.count - previewCount) more"))
                                .font(.system(size: 12)).foregroundStyle(Pal.accent)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
    }
}

// MARK: - Uninstall apps

private struct AppUninstallView: View {
    @ObservedObject var manager: SystemCleanerManager

    var body: some View {
        ListWithFooter {
            // Search + sort
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Pal.ink3)
                    TextField(tr("Search apps"), text: $manager.appSearchQuery)
                        .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Pal.ink)
                    if !manager.appSearchQuery.isEmpty {
                        Button { manager.appSearchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Pal.ink3)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Pal.card))

                JChip(text: tr("Size"), selected: manager.appSort == .size) { manager.appSort = .size }
                JChip(text: tr("Name"), selected: manager.appSort == .name) { manager.appSort = .name }
            }

            if let msg = manager.uninstallMessage {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(msg).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Pal.accent)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Pal.accentBg))
            }

            if manager.isScanningApps && manager.installedApps.isEmpty {
                HStack(spacing: 6) { Spinner(); Text(tr("Scanning apps")).font(.system(size: 12)).foregroundStyle(Pal.ink3) }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if manager.filteredApps.isEmpty {
                emptyState(icon: "app.dashed", text: tr("No apps found"))
            }

            ForEach(manager.filteredApps) { app in
                appCard(app)
            }
        } footer: {
            Button { manager.uninstallSelectedApps() } label: {
                if manager.isUninstalling {
                    HStack(spacing: 6) { Spinner(); Text(tr("Uninstalling…")) }
                } else if !manager.selectedAppIDs.isEmpty {
                    Text(tr("Uninstall \(manager.selectedAppIDs.count) app(s) · \(SystemCleanerManager.formatBytes(manager.selectedAppsBytes))"))
                } else {
                    Text(tr("Select apps to uninstall"))
                }
            }
            .buttonStyle(JButtonStyle())
            .disabled(manager.selectedAppIDs.isEmpty || manager.isUninstalling)
        }
    }

    @ViewBuilder private func appCard(_ app: InstalledAppItem) -> some View {
        let selected = manager.selectedAppIDs.contains(app.id)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                JCheck(state: selected ? .on : .off) { manager.toggleApp(app) }
                Image(nsImage: IconCache.icon(forFile: app.appURL.path, points: 28))
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink).lineLimit(1)
                    Text(app.appSizeFormatted).font(.system(size: 12)).foregroundStyle(Pal.ink3)
                }
                Spacer(minLength: 4)
                if selected {
                    Text(app.totalSizeFormatted).font(.system(size: 13, weight: .medium)).foregroundStyle(Pal.ink)
                }
            }
            .padding(10)
            .contentShape(Rectangle())
            .onTapGesture { manager.toggleApp(app) }

            if selected {
                VStack(spacing: 0) {
                    if app.isInspectingLeftovers {
                        JDivider()
                        HStack(spacing: 6) { Spinner(); Text(tr("Finding related files")).font(.system(size: 12)).foregroundStyle(Pal.ink3) }
                            .padding(.vertical, 8)
                    } else {
                        ForEach(app.leftovers) { left in
                            JDivider()
                            HStack(spacing: 10) {
                                JCheck(state: left.isSelected ? .on : .off) { manager.toggleLeftover(app: app.id, leftover: left.id) }
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(left.url.lastPathComponent).font(.system(size: 12)).foregroundStyle(Pal.ink)
                                        .lineLimit(1).truncationMode(.middle)
                                    Text(left.localizedCategoryName).font(.system(size: 11)).foregroundStyle(Pal.ink3)
                                }
                                Spacer(minLength: 4)
                                Text(left.sizeFormatted).font(.system(size: 12)).foregroundStyle(Pal.ink2)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                        }
                        if app.leftovers.isEmpty && app.leftoversLoaded {
                            JDivider()
                            Text(tr("No related files"))
                                .font(.system(size: 12)).foregroundStyle(Pal.ink3).padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Pal.accent : Color.clear, lineWidth: 1))
    }
}

// MARK: - Large files

private struct LargeFilesView: View {
    @ObservedObject var manager: SystemCleanerManager

    private let thresholds: [(Int, String)] = [(100, "100 MB"), (200, "200 MB"), (500, "500 MB"), (1024, "1 GB")]

    var body: some View {
        ListWithFooter {
            HStack(spacing: 6) {
                Text(tr("Larger than")).font(.system(size: 12)).foregroundStyle(Pal.ink3)
                ForEach(thresholds, id: \.0) { t in
                    JChip(text: t.1, selected: manager.largeFileThresholdMB == t.0) {
                        manager.largeFileThresholdMB = t.0
                        manager.scanLargeFiles()
                    }
                }
                Spacer(minLength: 0)
                if manager.isScanningLargeFiles { Spinner() }
            }

            if let msg = manager.largeFileMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text(msg).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Pal.ok)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Pal.okBg))
            }

            if manager.largeFiles.isEmpty && !manager.isScanningLargeFiles {
                emptyState(icon: "doc.text.magnifyingglass", text: tr("No files above this size"))
            }

            ForEach(manager.largeFiles) { file in
                fileRow(file)
            }
        } footer: {
            Button { manager.trashSelectedLargeFiles() } label: {
                if !manager.trashingFileIDs.isEmpty {
                    HStack(spacing: 6) { Spinner(); Text(tr("Moving…")) }
                } else if !manager.selectedLargeFileIDs.isEmpty {
                    Text(tr("Move \(manager.selectedLargeFileIDs.count) file(s) to Trash · \(SystemCleanerManager.formatBytes(manager.selectedLargeBytes))"))
                } else {
                    Text(tr("Select files to remove"))
                }
            }
            .buttonStyle(JButtonStyle())
            .disabled(manager.selectedLargeFileIDs.isEmpty || !manager.trashingFileIDs.isEmpty)
        }
    }

    private func fileRow(_ file: LargeFileItem) -> some View {
        let selected = manager.selectedLargeFileIDs.contains(file.id)
        return HStack(spacing: 10) {
            JCheck(state: selected ? .on : .off) { manager.toggleLargeFile(file.id) }
            Image(nsImage: IconCache.icon(forFile: file.url.path, points: 26)).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.system(size: 13)).foregroundStyle(Pal.ink).lineLimit(1).truncationMode(.middle)
                Text("\(file.folderName) · \(file.relativeDateFormatted)").font(.system(size: 11)).foregroundStyle(Pal.ink3).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(file.sizeFormatted).font(.system(size: 12, weight: .medium)).foregroundStyle(Pal.ink)
            Button { manager.revealInFinder(file.url) } label: {
                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Pal.ink2)
            }
            .buttonStyle(.plain)
            .help(tr("Reveal in Finder"))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Pal.accent : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { manager.toggleLargeFile(file.id) }
    }
}
