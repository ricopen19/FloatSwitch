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

    private func loadRunningApps() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
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
                  app.activationPolicy == .regular else { return }
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
}
