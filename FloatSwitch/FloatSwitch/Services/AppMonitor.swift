//
//  AppMonitor.swift
//  FloatSwitch
//

import AppKit

/// NSWorkspace 通知でアプリ一覧をリアルタイム監視する
@Observable
final class AppMonitor {
    private(set) var apps: [AppItem] = []

    /// 0.5 秒ごとに増加するカウンタ。AppViewModel.apps のウィンドウ判定を定期再評価させるために使う
    private(set) var windowCheckVersion: Int = 0

    private var observers: [NSObjectProtocol] = []
    private var windowCheckTimer: Timer?

    init() {
        loadRunningApps()
        setupObservers()
        startWindowCheckTimer()
    }

    deinit {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        windowCheckTimer?.invalidate()
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

    /// layer == 0（通常アプリウィンドウ）を持つアプリの PID セットを返す
    ///
    /// `CGWindowListCopyWindowInfo` を使うため Accessibility 権限不要。
    /// メニューバー常駐アプリ（layer 24-25）やデスクトップ（負レイヤー）は除外される。
    static func pidsWithWindows() -> Set<pid_t> {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var pids = Set<pid_t>()
        for info in list {
            guard let pid   = info[kCGWindowOwnerPID as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue }
            pids.insert(pid_t(pid))
        }
        return pids
    }

    // MARK: - Private

    private func startWindowCheckTimer() {
        windowCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.windowCheckVersion += 1
        }
    }
}
