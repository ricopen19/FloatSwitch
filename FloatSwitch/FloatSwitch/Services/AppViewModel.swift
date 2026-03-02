//
//  AppViewModel.swift
//  FloatSwitch
//

import AppKit
import SwiftUI

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
    let customization = AppCustomization()

    var barSize: BarSize = .medium

    /// true のとき ウィンドウを持たない常駐アプリ（.regular でウィンドウなし / .accessory）も表示する
    var showResidentApps: Bool = false

    var apps: [AppItem] {
        // windowCheckVersion を参照することで 0.5 秒ごとに再評価を強制する
        _ = appMonitor.windowCheckVersion

        // CGWindowList で layer 0...3 のウィンドウを持つ PID を一括取得（権限不要）
        let windowedPIDs = AppMonitor.pidsWithWindows()

        // 通常の表示条件でフィルタ
        let visible = appMonitor.apps.filter { item in
            guard case .app(let runningApp) = item.kind else { return true }

            // Dock の丸が付くのは .regular のみ。 .accessory などは常に非表示。
            guard runningApp.activationPolicy == .regular else { return false }
            // LSUIElement / LSBackgroundOnly は Dock に出ない想定なので常に非表示
            if Self.isAgentApp(runningApp) { return false }

            // .regular: ウィンドウ（layer 0...3）を持つなら常に表示、なければ toggle 次第
            return windowedPIDs.contains(runningApp.processIdentifier) || showResidentApps
        }

        // 隠しリストに含まれる bundleID を除外
        let hidden = customization.config.hiddenBundleIDs
        let filtered = visible.filter { item in
            guard case .app(let app) = item.kind else { return true }
            return !(hidden.contains(app.bundleIdentifier ?? ""))
        }

        // orderedBundleIDs の順でソート（未指定は末尾に起動順で追加）
        let ordered = customization.config.orderedBundleIDs
        return filtered.sorted { aItem, bItem in
            guard case .app(let appA) = aItem.kind,
                  case .app(let appB) = bItem.kind else { return false }
            let iA = ordered.firstIndex(of: appA.bundleIdentifier ?? "") ?? Int.max
            let iB = ordered.firstIndex(of: appB.bundleIdentifier ?? "") ?? Int.max
            return iA < iB
        }
    }

    // MARK: - Reorder

    /// ドラッグ並び替え後に表示順序を永続化する
    ///
    /// - Parameters:
    ///   - fromBundleID: ドラッグ元の bundleID
    ///   - toBundleID: ドロップ先の bundleID
    func reorderApps(fromBundleID: String, toBundleID: String) {
        var bundleIDs = apps.compactMap { item -> String? in
            guard case .app(let app) = item.kind else { return nil }
            return app.bundleIdentifier
        }
        guard let fromIdx = bundleIDs.firstIndex(of: fromBundleID),
              let toIdx = bundleIDs.firstIndex(of: toBundleID),
              fromIdx != toIdx else { return }
        bundleIDs.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        customization.updateOrder(bundleIDs: bundleIDs)
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
