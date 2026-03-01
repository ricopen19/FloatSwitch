//
//  AppViewModel.swift
//  FloatSwitch
//

import AppKit

// MARK: - BarSize

/// バー全体のサイズプリセット
enum BarSize: String, CaseIterable {
    case small  = "小"
    case medium = "中"
    case large  = "大"

    var iconSize: CGFloat {
        switch self {
        case .small:  return 22
        case .medium: return 32
        case .large:  return 46
        }
    }

    /// NSPanel の高さ（2 行 + 弧 + 拡大マージン）
    var panelHeight: CGFloat {
        let rowHeight = iconSize + 28   // アイコン + ラベル + padding
        let magnifyMargin = iconSize * 0.8  // scaleEffect 最大拡大分の上マージン
        let arcDepth: CGFloat = 22
        let divider: CGFloat = 1
        return magnifyMargin + rowHeight * 2 + divider + arcDepth + 8
    }
}

// MARK: - AppViewModel

/// AppMonitor と FinderMonitor を束ねる状態管理クラス
@Observable
final class AppViewModel {
    let appMonitor = AppMonitor()
    let finderMonitor = FinderMonitor()

    var barSize: BarSize = .medium

    /// true のとき ウィンドウを持たない常駐アプリ（.regular でウィンドウなし / .accessory）も表示する
    var showResidentApps: Bool = false
    /// true のとき フィルタ判定をコンソールに出力する
    var debugAppFiltering: Bool = false
    /// デバッグ出力の対象アプリ名（空なら全件）
    var debugFilterNames: Set<String> = ["Nani", "VoiceInk", "QuickOCR"]

    private var lastDebugVersion: Int = -1
    /// Space 切替直後の一時的なウィンドウ判定欠落を吸収する保持秒数
    private let windowPresenceGrace: TimeInterval = 1.8
    /// PID ごとの「最後にウィンドウありだった時刻」
    private var lastSeenWindowAt: [pid_t: Date] = [:]

    var apps: [AppItem] {
        // windowCheckVersion を参照することで 0.5 秒ごとに再評価を強制する
        _ = appMonitor.windowCheckVersion

        // AppMonitor 側で定期更新したウィンドウ判定キャッシュを使う
        let windowedPIDs = appMonitor.windowedPIDs
        let effectiveWindowedPIDs = windowedPIDsWithGrace(current: windowedPIDs)

        if debugAppFiltering,
           appMonitor.windowCheckVersion % 4 == 0,
           lastDebugVersion != appMonitor.windowCheckVersion {
            lastDebugVersion = appMonitor.windowCheckVersion
            debugPrintFilter(rawWindowedPIDs: windowedPIDs, effectiveWindowedPIDs: effectiveWindowedPIDs)
        }

        return appMonitor.apps.filter { item in
            guard case .app(let runningApp) = item.kind else { return true }

            // Dock の丸が付くのは .regular のみ。 .accessory などは常に非表示。
            guard runningApp.activationPolicy == .regular else { return false }
            // LSUIElement / LSBackgroundOnly は Dock に出ない想定なので常に非表示
            if Self.isAgentApp(runningApp) { return false }

            // .regular: ウィンドウ（layer 0）を持つなら常に表示、なければ toggle 次第
            return effectiveWindowedPIDs.contains(runningApp.processIdentifier) || showResidentApps
        }
    }

    // MARK: - Private

    private static func isAgentApp(_ app: NSRunningApplication) -> Bool {
        guard let bundleURL = app.bundleURL,
              let bundle = Bundle(url: bundleURL),
              let info = bundle.infoDictionary else { return false }
        if let uiElement = info["LSUIElement"] as? Bool, uiElement { return true }
        if let backgroundOnly = info["LSBackgroundOnly"] as? Bool, backgroundOnly { return true }
        return false
    }

    private func windowedPIDsWithGrace(current: Set<pid_t>) -> Set<pid_t> {
        let now = Date()
        for pid in current {
            lastSeenWindowAt[pid] = now
        }

        let aliveAppPIDs: Set<pid_t> = Set(
            appMonitor.apps.compactMap { item in
                guard case .app(let app) = item.kind else { return nil }
                return app.processIdentifier
            }
        )

        lastSeenWindowAt = lastSeenWindowAt.filter { pid, date in
            guard aliveAppPIDs.contains(pid) else { return false }
            return now.timeIntervalSince(date) <= windowPresenceGrace
        }

        return current.union(lastSeenWindowAt.keys)
    }

    private func debugPrintFilter(rawWindowedPIDs: Set<pid_t>, effectiveWindowedPIDs: Set<pid_t>) {
        var debugPIDs: Set<pid_t> = []

        print(
            "[FloatSwitch][Debug] showResidentApps=\(showResidentApps) " +
            "windowedPIDs(raw/effective)=\(rawWindowedPIDs.count)/\(effectiveWindowedPIDs.count)"
        )
        for item in appMonitor.apps {
            guard case .app(let runningApp) = item.kind else { continue }
            if !debugFilterNames.isEmpty, !debugFilterNames.contains(item.name) { continue }
            let pid = runningApp.processIdentifier
            debugPIDs.insert(pid)
            let policy = runningApp.activationPolicy
            let isRegular = policy == .regular
            let isAgent = Self.isAgentApp(runningApp)
            let rawHasWindow = rawWindowedPIDs.contains(pid)
            let hasWindow = effectiveWindowedPIDs.contains(pid)
            let shouldShow = isRegular && !isAgent && (hasWindow || showResidentApps)

            print(
                " - \(item.name) pid=\(pid) policy=\(policy) agent=\(isAgent) " +
                "window(raw/effective)=\(rawHasWindow)/\(hasWindow) show=\(shouldShow)"
            )
        }

        if !debugPIDs.isEmpty {
            let lines = AppMonitor.windowDebugLines(for: debugPIDs)
            for line in lines {
                print("   window: \(line)")
            }
        }
    }

    var folders: [AppItem] { finderMonitor.folders }
    var iconSize: CGFloat { barSize.iconSize }

    /// 表示中のアプリ・フォルダ数からパネル幅を動的計算する
    ///
    /// MagnifyingIconRow のレイアウト定数と合わせる:
    ///   itemFrameWidth = iconSize + 16, spacing = 6, horizontalPadding = 8
    var panelWidth: CGFloat {
        let itemFrameWidth = iconSize + 16
        let spacing: CGFloat = 6
        let padding: CGFloat = 8  // .padding(.horizontal, 8) → 両側で 16pt

        func rowWidth(_ count: Int) -> CGFloat {
            guard count > 0 else { return 0 }
            return CGFloat(count) * itemFrameWidth
                + CGFloat(count - 1) * spacing
                + padding * 2
        }

        let contentWidth = max(rowWidth(apps.count), rowWidth(folders.count))
        let maxWidth = NSScreen.main?.visibleFrame.width ?? 1200
        return min(max(contentWidth, 120), maxWidth)
    }
}
