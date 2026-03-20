//
//  AppMonitor.swift
//  FloatSwitch
//

import AppKit

/// NSWorkspace 通知でアプリ一覧をリアルタイム監視する
@Observable
final class AppMonitor {
    private(set) var apps: [AppItem] = []

    /// ウィンドウ状態が実際に変化した場合のみ増加するカウンタ。AppViewModel.apps の再評価トリガー。
    private(set) var windowCheckVersion: Int = 0

    /// 直近の CGWindowListCopyWindowInfo 結果をキャッシュ。AppViewModel から直接参照する。
    private(set) var cachedWindowPIDs: Set<pid_t> = []

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

    /// 画面上に表示されている通常アプリウィンドウ（layer 0-3）を持つ PID セットを返す
    ///
    /// `CGWindowListCopyWindowInfo` を使うため Accessibility 権限不要。
    /// メニューバー常駐アプリ（layer 24-25）やデスクトップ（負レイヤー）は除外される。
    static func pidsWithWindows() -> Set<pid_t> {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var pids = Set<pid_t>()
        let minWindowSide: Double = 40
        let minWindowHeightWithTitle: Double = 40
        let minWindowHeightNoTitle: Double = 80

        for info in list {
            guard let pid   = info[kCGWindowOwnerPID as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  (0...3).contains(layer) else { continue }

            if let onScreen = info[kCGWindowIsOnscreen as String] as? Bool, onScreen == false {
                continue
            }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                continue
            }
            if let bounds = info[kCGWindowBounds as String] as? [String: Any],
               let width = bounds["Width"] as? Double,
               let height = bounds["Height"] as? Double {
                if width <= 1 || height <= 1 {
                    continue
                }
                let name = (info[kCGWindowName as String] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let hasTitle = !name.isEmpty
                if hasTitle {
                    if height < minWindowHeightWithTitle { continue }
                } else {
                    if height < minWindowHeightNoTitle { continue }
                }
                let largeEnough = width >= minWindowSide && height >= minWindowSide
                if !hasTitle && !largeEnough {
                    continue
                }
            }

            pids.insert(pid_t(pid))
        }
        return pids
    }

    // MARK: - Private

    private func startWindowCheckTimer() {
        // 初回キャッシュ
        cachedWindowPIDs = Self.pidsWithWindows()

        windowCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let latest = Self.pidsWithWindows()
            if latest != self.cachedWindowPIDs {
                self.cachedWindowPIDs = latest
                self.windowCheckVersion += 1
            }
        }
    }
}
