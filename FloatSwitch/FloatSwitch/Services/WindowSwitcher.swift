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

    // MARK: - State

    /// プロセスごとの AX 巡回インデックス
    private static var cycleIndex: [pid_t: Int] = [:]

    /// 直前にアクティブ化したアプリの PID
    ///
    /// Chrome など click 時に `isActive` が false になるアプリは
    /// `app.isActive` ではなく「同じアプリアイコンを連続タップしたか」で巡回を判定する。
    private static var lastActivatedPID: pid_t = 0

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

    /// クリック時の基本動作: 最前面ウィンドウを呼び出す / 複数ウィンドウを巡回する
    ///
    /// ## 設計方針
    ///
    /// ### `isActive` に頼らない巡回判定
    /// FloatSwitch のクリック時、Chrome 等の一部アプリは `NSRunningApplication.isActive`
    /// が一瞬 false になる。そのため `isActive` ではなく `lastActivatedPID`（直前に
    /// アクティブ化した PID）との一致で「同じアプリアイコンを連続タップ = 巡回意図」を判定する。
    ///
    /// ### 3段階フォールバック
    /// 1. AX で複数ウィンドウが見える → `kAXRaiseAction` で巡回
    /// 2. AX は 1 枚だが CGWindowList では複数確認できる（Chrome AX 制限）→ `Cmd+\`` で巡回
    /// 3. どちらも単一 / 初回タップ → `activate()` で macOS に委ねる
    ///
    /// ### Space をまたぐ場合
    /// `kAXRaiseAction` は Space をまたがないため、別 Space のウィンドウへは `activate()` を使う。
    static func activateMostRecent(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        // 「同じアプリを連続タップ」かどうかを lastActivatedPID で判定
        let isContinuousTap = (lastActivatedPID == pid)
        lastActivatedPID = pid

        if AXIsProcessTrusted() {
            let ws = windows(for: pid).filter(\.isAppWindow)

            // ① AX 巡回: 同じアプリ連打 + AX で複数ウィンドウが見える
            if isContinuousTap && ws.count > 1 {
                let current = cycleIndex[pid] ?? 0
                let next = (current + 1) % ws.count
                cycleIndex[pid] = next
                unminimizeAndRaise(ws[next], app: app)
                return
            }

            // ② 最小化解除: activate() だけでは解除されないため AX を使う
            if let minimized = ws.first(where: { $0.isMinimized }) {
                unminimizeAndRaise(minimized, app: app)
                return
            }
        }

        // 初回タップ / 別アプリへの切り替え: macOS の Space 自動切り替えに委ねる
        // 別 Space のウィンドウへは公開 API では届かないため activate() で macOS に委ねる
        cycleIndex[pid] = 0
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
