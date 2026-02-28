//
//  AppMonitor.swift
//  FloatSwitch
//

import AppKit

/// NSWorkspace 通知でアプリ一覧をリアルタイム監視する
@Observable
final class AppMonitor {
    private(set) var apps: [AppItem] = []

    private var observers: [NSObjectProtocol] = []

    init() {
        loadRunningApps()
        setupObservers()
    }

    deinit {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    /// Accessibility 権限付与後などに外部から呼び出してアプリ一覧を再読み込みする
    func refreshApps() {
        loadRunningApps()
    }

    private func loadRunningApps() {
        // .prohibited（システム内部プロセス等）のみ除外し、あとは AppViewModel でフィルタ
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map { AppItem(app: $0) }
    }

    private func setupObservers() {
        let center = NSWorkspace.shared.notificationCenter

        let launch = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy != .prohibited else { return }
            self?.apps.append(AppItem(app: app))
        }

        let terminate = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.apps.removeAll { $0.id == "app-\(app.processIdentifier)" }
        }

        let hide = center.addObserver(
            forName: NSWorkspace.didHideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.reloadApp(from: notification)
        }

        let unhide = center.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.reloadApp(from: notification)
        }

        observers = [launch, terminate, hide, unhide]
    }

    private func reloadApp(from notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if let index = apps.firstIndex(where: { $0.id == "app-\(app.processIdentifier)" }) {
            apps[index] = AppItem(app: app)
        }
    }

    /// Accessibility API でアプリが1つ以上のウィンドウを持つか確認する
    ///
    /// - Note: `AXIsProcessTrusted()` が false の場合は常に false を返す
    static func hasWindows(pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        return !windows.isEmpty
    }
}
