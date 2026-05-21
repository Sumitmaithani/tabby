import AppKit
import SwiftUI

@MainActor
final class FirstRunWindowController: NSWindowController, NSWindowDelegate {
    private let store: BookmarkStore
    private let settingsStore: SettingsStore
    private let coordinator: ImportCoordinator

    init(store: BookmarkStore, settingsStore: SettingsStore, coordinator: ImportCoordinator) {
        self.store = store
        self.settingsStore = settingsStore
        self.coordinator = coordinator

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Tabby"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        window.contentViewController = NSHostingController(
            rootView: FirstRunRootView(onClose: { [weak self] in
                self?.close()
            })
            .environmentObject(store)
            .environmentObject(settingsStore)
            .environmentObject(coordinator)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if !settingsStore.settings.hasCompletedFirstRunImport {
            settingsStore.settings.hasSkippedImportOnboarding = true
        }
        coordinator.dismiss()
    }
}

private struct FirstRunRootView: View {
    @EnvironmentObject var coordinator: ImportCoordinator
    @EnvironmentObject var settingsStore: SettingsStore
    let onClose: () -> Void

    @State private var step: FirstRunStep = .welcome

    enum FirstRunStep {
        case welcome
        case permission
        case flow
    }

    var body: some View {
        Group {
            switch step {
            case .welcome:
                welcomeStep
            case .permission:
                BrowserPermissionView(showSkip: true, onSkip: skipAll)
                    .padding(28)
            case .flow:
                firstRunFlow
            }
        }
        .frame(width: 480, height: 360)
        .onAppear { bootstrap() }
        .onChange(of: coordinator.phase) { phase in
            handlePhaseChange(phase)
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Text("Welcome to Tabby")
                .font(.system(size: 18, weight: .semibold))

            Text("Import bookmarks from the browsers you already use — one click, no export files.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Get started") {
                if FullDiskAccessChecker.isGranted() {
                    step = .flow
                    coordinator.startBrowserFlow()
                } else {
                    step = .permission
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Skip for now") { skipAll() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    @ViewBuilder
    private var firstRunFlow: some View {
        switch coordinator.phase {
        case .needsPermission:
            BrowserPermissionView(showSkip: true, onSkip: skipAll)
                .padding(28)
        case .scanningBrowsers:
            BrowserScanningView()
                .padding(28)
        case .browserChoices(let results):
            BrowserImportChoicesView(results: results, compactFooter: true)
                .padding(24)
        case .importing:
            FirstRunImportingView()
                .padding(28)
        case .success(let result):
            FirstRunSuccessView(result: result, onDone: finish)
                .padding(28)
        case .partial(let result):
            FirstRunSuccessView(result: result, onDone: finish)
                .padding(28)
        case .error(let kind):
            FirstRunErrorView(kind: kind, onClose: onClose)
                .padding(28)
        default:
            BrowserScanningView()
                .padding(28)
        }
    }

    private func bootstrap() {
        if FullDiskAccessChecker.consumeResumeAfterGrant() {
            step = .flow
            coordinator.resumeBrowserFlowAfterPermission()
            return
        }
        if FullDiskAccessChecker.isGranted() {
            step = .flow
            coordinator.startBrowserFlow()
        }
    }

    private func handlePhaseChange(_ phase: ImportCoordinator.Phase) {
        switch phase {
        case .success, .partial:
            settingsStore.settings.hasCompletedFirstRunImport = true
        default:
            break
        }
    }

    private func skipAll() {
        settingsStore.settings.hasSkippedImportOnboarding = true
        coordinator.dismiss()
        onClose()
    }

    private func finish() {
        settingsStore.settings.hasCompletedFirstRunImport = true
        coordinator.dismiss()
        onClose()
    }
}

private struct FirstRunImportingView: View {
    @EnvironmentObject var coordinator: ImportCoordinator

    var body: some View {
        VStack(spacing: 16) {
            Text("Importing…")
                .font(.system(size: 14, weight: .medium))
            if let p = coordinator.progress {
                ProgressView(value: Double(p.done), total: Double(p.total))
                Text("\(p.done) / \(p.total)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            Button("Cancel") { coordinator.cancel() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

private struct FirstRunSuccessView: View {
    @EnvironmentObject var coordinator: ImportCoordinator
    let result: ImportResult
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Imported \(result.imported) bookmark\(result.imported == 1 ? "" : "s")")
                .font(.system(size: 15, weight: .semibold))

            if result.tagsCreated > 0 {
                Text("\(result.tagsCreated) tag\(result.tagsCreated == 1 ? "" : "s") created")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if result.duplicatesSkipped > 0 {
                Text("\(result.duplicatesSkipped) duplicate\(result.duplicatesSkipped == 1 ? "" : "s") skipped")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(Constants.successAutoDismissSeconds * 1_000_000_000))
                if case .success = coordinator.phase {
                    onDone()
                } else if case .partial = coordinator.phase {
                    onDone()
                }
            }
        }
    }
}

private struct FirstRunErrorView: View {
    @EnvironmentObject var coordinator: ImportCoordinator
    let kind: ImportErrorKind
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.system(size: 14, weight: .semibold))
            Text(kind.userFacingLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Button("Try again") { coordinator.scanBrowsers() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Skip for now", action: onClose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
