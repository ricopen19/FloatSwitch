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

    // MARK: - Internal state

    /// プロセスごとの巡回インデックス。AX がウィンドウ順序を即時更新しないアプリ（Chrome 等）対策。
    private static var cycleIndex: [pid_t: Int] = [:]

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
    /// ## 設計方針
    ///
    /// `kAXRaiseAction` はウィンドウを前面に出せるが **Space をまたがない**。
    /// そのため複数 Space / 外部ディスプレイの場合に常に同じ Space のウィンドウが
    /// 前面に来てしまう問題がある。
    ///
    /// 非アクティブ時は `app.activate()` だけを使うことで macOS に Space 切り替えを
    /// 委ね、最後に使ったウィンドウが正しく前面に出るようにする。
    ///
    /// AX は以下の 2 ケースにのみ使用する:
    /// - 同 Space 内での **ウィンドウ巡回**（アクティブ + 複数ウィンドウ）
    /// - **最小化ウィンドウの復元**（`activate()` だけでは解除されない）
    static func activateMostRecent(_ app: NSRunningApplication) {
        if AXIsProcessTrusted() {
            let ws = windows(for: app.processIdentifier).filter(\.isAppWindow)

            // ① 巡回: アクティブ + 複数ウィンドウ → static なインデックスで順番に進む
            //
            // kAXWindowsAttribute のウィンドウ順序が raise 後に更新されないアプリ（Chrome 等）のため、
            // AX の Z 順に依存せず cycleIndex で自前管理する。
            if app.isActive && ws.count > 1 {
                let pid = app.processIdentifier
                let current = cycleIndex[pid] ?? 0
                // ウィンドウが閉じられてインデックスが範囲外になっても modulo で補正
                let next = (current + 1) % ws.count
                cycleIndex[pid] = next
                unminimizeAndRaise(ws[next], app: app)
                return
            }

            // ② 最小化解除: activate() だけでは最小化は解除されないため AX を使う
            if let minimized = ws.first(where: { $0.isMinimized }) {
                unminimizeAndRaise(minimized, app: app)
                return
            }
        }

        // 非アクティブ時: activate() に委ね、巡回インデックスをリセットする
        // - macOS が「最後に使用した Space のウィンドウ」へ自動切り替えする
        // - kAXRaiseAction は Space をまたがないため外部ディスプレイのウィンドウに届かない
        cycleIndex[app.processIdentifier] = 0
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
