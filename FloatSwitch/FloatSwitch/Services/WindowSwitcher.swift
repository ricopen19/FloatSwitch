//
//  WindowSwitcher.swift
//  FloatSwitch
//

import AppKit

// MARK: - WindowInfo

/// AX ウィンドウ1件のスナップショット
struct WindowInfo: Identifiable {
    let id: UUID = UUID()
    let axElement: AXUIElement
    let title: String
    let isMinimized: Bool
    let size: CGSize

    /// 内部ウィンドウ・拡張機能バックグラウンドページを除いた「実際のアプリウィンドウ」かどうか
    ///
    /// 最小化ウィンドウは AX でサイズが 0 になる場合があるため、最小化フラグで別途包含する。
    var isAppWindow: Bool {
        isMinimized || (size.width >= 200 && size.height >= 150)
    }
}

// MARK: - WindowSwitcher

/// Accessibility API を使ったウィンドウ切り替えユーティリティ
///
/// - 全メソッドが static：インスタンス不要
/// - AX 権限がない場合は `NSRunningApplication.activate()` にフォールバック
enum WindowSwitcher {

    // MARK: - Public

    /// アプリの全ウィンドウを AX 経由で取得する
    ///
    /// AX 権限がない / ウィンドウ取得失敗の場合は空配列を返す
    static func windows(for pid: pid_t) -> [WindowInfo] {
        guard AXIsProcessTrusted() else { return [] }

        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return [] }

        return axWindows.compactMap { axWindow in
            var titleRef: CFTypeRef?
            var minimizedRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef)
            AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)

            let title     = titleRef as? String ?? ""
            let minimized = minimizedRef as? Bool ?? false
            var cgSize = CGSize.zero
            if let sv = sizeRef {
                // CFTypeRef → AXValue: Swift の as?/as! どちらも CF 型では警告/エラーになるため
                // unsafeBitCast を使い、AXValueGetType で型を確認してから値を取得する
                let axValue = unsafeBitCast(sv, to: AXValue.self)
                if AXValueGetType(axValue) == .cgSize {
                    AXValueGetValue(axValue, .cgSize, &cgSize)
                }
            }
            return WindowInfo(axElement: axWindow, title: title, isMinimized: minimized, size: cgSize)
        }
    }

    /// クリック時の基本動作: 最前面ウィンドウを呼び出す
    ///
    /// - AX 権限あり: AX で frontmost ウィンドウを raise（最小化されていれば解除）→ activate
    /// - AX 権限なし / AX でウィンドウ取得失敗: `activate()` のみにフォールバック
    ///
    /// `activate()` だけでは Space 切り替えは起きるがウィンドウが前面に来ないケースがある。
    /// `kAXRaiseAction` を明示的に呼ぶことで確実に最前面に持ってくる。
    static func activateMostRecent(_ app: NSRunningApplication) {
        if AXIsProcessTrusted() {
            // 内部ウィンドウ（拡張機能 BG ページ等）を除いた実際のウィンドウだけで巡回する
            let ws = windows(for: app.processIdentifier).filter(\.isAppWindow)
            if !ws.isEmpty {
                // AX ウィンドウリストは z-order 順（frontmost が ws[0]）
                // - 既にアクティブ & 複数ウィンドウ → ws[1] を raise して巡回
                // - 非アクティブ or 1ウィンドウ   → ws[0]（最近使ったウィンドウ）を raise
                let target = (app.isActive && ws.count > 1) ? ws[1] : ws[0]
                unminimizeAndRaise(target, app: app)
                return
            }
        }
        // AX 権限なし、または AX ウィンドウが取得できない場合のフォールバック
        if !app.activate(options: .activateIgnoringOtherApps),
           let bundleURL = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([], withApplicationAt: bundleURL,
                                    configuration: config, completionHandler: nil)
        }
    }

    /// 右クリックから選択した特定ウィンドウをアクティブ化する
    static func activate(_ window: WindowInfo, app: NSRunningApplication) {
        unminimizeAndRaise(window, app: app)
    }

    /// フォルダを Finder で開く
    static func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private static func unminimizeAndRaise(_ window: WindowInfo, app: NSRunningApplication) {
        if window.isMinimized {
            AXUIElementSetAttributeValue(
                window.axElement, kAXMinimizedAttribute as CFString, false as CFBoolean
            )
        }
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        app.activate(options: .activateIgnoringOtherApps)
    }
}
