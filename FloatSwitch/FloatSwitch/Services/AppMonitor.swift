//
//  AppMonitor.swift
//  FloatSwitch
//

import AppKit
import ApplicationServices

/// NSWorkspace 通知でアプリ一覧をリアルタイム監視する
@Observable
final class AppMonitor {
    private(set) var apps: [AppItem] = []
    /// 直近のウィンドウ判定結果キャッシュ（0.5 秒ごとに更新）
    private(set) var windowedPIDs: Set<pid_t> = []

    /// 0.5 秒ごとに増加するカウンタ。AppViewModel.apps のウィンドウ判定を定期再評価させるために使う
    private(set) var windowCheckVersion: Int = 0

    private var observers: [NSObjectProtocol] = []
    private var windowCheckTimer: Timer?
    private let windowQueryQueue = DispatchQueue(label: "FloatSwitch.AppMonitor.WindowQuery", qos: .utility)
    private var isRefreshingWindowPIDs = false

    init() {
        Self.requestAccessibilityIfNeeded()
        loadRunningApps()
        setupObservers()
        refreshWindowedPIDs()
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

    /// Accessibility が許可されていれば AX 経由で、
    /// 未許可なら CGWindowList で「ウィンドウを持つ PID」を返す
    ///
    /// `CGWindowListCopyWindowInfo` を使うため Accessibility 権限不要。
    /// メニューバー常駐アプリ（layer 24-25）やデスクトップ（負レイヤー）は除外される。
    static func pidsWithWindows() -> Set<pid_t> {
        if AXIsProcessTrusted() {
            // AX は Space 切替直後に一時的な取りこぼしが起きることがあるため、
            // CG の結果を併用して偽陰性を減らす。
            return pidsWithAXWindows().union(pidsWithCGWindows())
        }
        return pidsWithCGWindows()
    }

    /// 画面上に表示されている通常アプリウィンドウ（layer 0-3）を持つ PID セットを返す
    private static func pidsWithCGWindows() -> Set<pid_t> {
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

            let onScreen = boolValue(info[kCGWindowIsOnscreen as String]) ?? false
            guard (doubleValue(info[kCGWindowAlpha as String]) ?? 0) > 0 else {
                continue
            }
            if let bounds = info[kCGWindowBounds as String] as? [String: Any],
               let width = doubleValue(bounds["Width"]),
               let height = doubleValue(bounds["Height"]) {
                if width <= 1 || height <= 1 {
                    continue
                }
                let name = (info[kCGWindowName as String] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let hasTitle = !name.isEmpty
                if !onScreen && !hasTitle {
                    continue
                }
                if hasTitle {
                    if height < minWindowHeightWithTitle { continue }
                } else if height < minWindowHeightNoTitle {
                    continue
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

    /// Accessibility 経由で「標準ウィンドウ」を持つ PID セットを返す
    private static func pidsWithAXWindows() -> Set<pid_t> {
        var pids = Set<pid_t>()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }

        for app in apps {
            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)
            guard let windows = copyAXArray(axApp, kAXWindowsAttribute as CFString) else { continue }
            if windows.contains(where: { isAcceptableAXWindow($0) }) {
                pids.insert(pid)
            }
        }
        return pids
    }

    /// デバッグ用: 指定 PID のウィンドウ情報を文字列で返す
    static func windowDebugLines(for pids: Set<pid_t>) -> [String] {
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo(
                [.optionAll, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else { return [] }

        var lines: [String] = []
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int else { continue }
            let spid = pid_t(pid)
            guard pids.contains(spid) else { continue }

            let owner = (info[kCGWindowOwnerName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let layer = info[kCGWindowLayer as String] as? Int ?? -999
            let onScreen = boolValue(info[kCGWindowIsOnscreen as String]) ?? false
            let alpha = doubleValue(info[kCGWindowAlpha as String]) ?? -1
            let name = (info[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            var width: Double = -1
            var height: Double = -1
            if let bounds = info[kCGWindowBounds as String] as? [String: Any] {
                width = doubleValue(bounds["Width"]) ?? -1
                height = doubleValue(bounds["Height"]) ?? -1
            }

            lines.append(
                "pid=\(pid) owner=\"\(owner)\" layer=\(layer) onScreen=\(onScreen) alpha=\(alpha) size=\(Int(width))x\(Int(height)) name=\"\(name)\""
            )
        }
        return lines
    }

    // MARK: - Private

    private static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func copyAXArray(_ element: AXUIElement, _ attr: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attr, &value)
        guard result == .success, let array = value as? [AXUIElement] else { return nil }
        return array
    }

    private static func axString(_ element: AXUIElement, _ attr: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attr, &value)
        guard result == .success, let str = value as? String else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isAcceptableAXWindow(_ window: AXUIElement) -> Bool {
        if let role = axString(window, kAXRoleAttribute as CFString),
           role != (kAXWindowRole as String) {
            return false
        }

        if axBool(window, kAXMinimizedAttribute as CFString) == true {
            return false
        }

        if let subrole = axString(window, kAXSubroleAttribute as CFString) {
            let okSubroles: Set<String> = [
                kAXStandardWindowSubrole as String,
                kAXDialogSubrole as String,
                kAXSystemDialogSubrole as String
            ]
            if okSubroles.contains(subrole) {
                return true
            }
        }

        // サブロールが取れないケース:
        // タイトルあり、または最低限のサイズがある Window は許可する。
        if axString(window, kAXTitleAttribute as CFString) != nil {
            return true
        }

        if let size = axSize(window, kAXSizeAttribute as CFString),
           size.width >= 40, size.height >= 40 {
            return true
        }

        return false
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String {
            let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lower == "1" || lower == "true" { return true }
            if lower == "0" || lower == "false" { return false }
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func axBool(_ element: AXUIElement, _ attr: CFString) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attr, &value)
        guard result == .success else { return nil }
        return boolValue(value)
    }

    private static func axSize(_ element: AXUIElement, _ attr: CFString) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attr, &value)
        guard result == .success,
              let raw = value,
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(raw, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    // MARK: - Private

    private func startWindowCheckTimer() {
        windowCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshWindowedPIDs()
        }
    }

    private func refreshWindowedPIDs() {
        guard !isRefreshingWindowPIDs else { return }
        isRefreshingWindowPIDs = true

        windowQueryQueue.async { [weak self] in
            let pids = Self.pidsWithWindows()
            DispatchQueue.main.async {
                guard let self else { return }
                self.windowedPIDs = pids
                self.windowCheckVersion += 1
                self.isRefreshingWindowPIDs = false
            }
        }
    }
}
