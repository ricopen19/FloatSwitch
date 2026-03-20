//
//  AppViewModel.swift
//  FloatSwitch
//

import AppKit
import SwiftUI

// MARK: - BarOrientation

/// バーの配置方向
enum BarOrientation: String, CaseIterable {
    case horizontal = "横"
    case vertical   = "縦"
}

/// 縦型バーの画面配置
enum BarPosition: String, CaseIterable {
    case left  = "左"
    case right = "右"
}

// MARK: - GradientPreset

/// ホバー時のグラデーション背景プリセット
enum GradientPreset: String, CaseIterable, Identifiable {
    case none    = "なし"
    case pink    = "ピンク"
    case blue    = "ブルー"
    case purple  = "パープル"
    case orange  = "オレンジ"
    case mint    = "ミント"

    var id: String { rawValue }

    /// グラデーションの色ペア（start, end）
    var colors: (Color, Color)? {
        switch self {
        case .none:   return nil
        case .pink:   return (Color(red: 0.90, green: 0.55, blue: 0.70), Color(red: 0.70, green: 0.50, blue: 0.80))
        case .blue:   return (Color(red: 0.50, green: 0.70, blue: 0.90), Color(red: 0.45, green: 0.80, blue: 0.85))
        case .purple: return (Color(red: 0.70, green: 0.50, blue: 0.85), Color(red: 0.55, green: 0.45, blue: 0.82))
        case .orange: return (Color(red: 0.95, green: 0.65, blue: 0.50), Color(red: 0.90, green: 0.55, blue: 0.65))
        case .mint:   return (Color(red: 0.50, green: 0.85, blue: 0.75), Color(red: 0.45, green: 0.75, blue: 0.78))
        }
    }

    /// プレビュー用の代表色
    var previewColor: Color? {
        colors?.0
    }
}

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

    /// NSPanel の高さ（ベース値。hoverScale を含む実高さは AppViewModel.panelHeight で算出）
    var basePanelHeight: CGFloat {
        let iconRow = iconSize + 4          // アイコン
        let expandedPadding: CGFloat = 16   // 8 * 2（膨張時の上下パディング）
        let labelSpace: CGFloat = 10        // ホバー時ラベル表示スペース
        return expandedPadding + iconRow + labelSpace
    }
}

// MARK: - AppViewModel

/// AppMonitor と FinderMonitor を束ねる状態管理クラス
@Observable
final class AppViewModel {
    let appMonitor = AppMonitor()
    let finderMonitor = FinderMonitor()
    let customization = AppCustomization()
    let hotkeySettings = HotkeySettings()

    init() {
        loadAppearance()
    }

    var barSize: BarSize = .medium {
        didSet { saveAppearance() }
    }
    var orientation: BarOrientation = .horizontal {
        didSet { saveAppearance() }
    }
    var position: BarPosition = .right {
        didSet { saveAppearance() }
    }
    var gradientPreset: GradientPreset = .none {
        didSet { saveAppearance() }
    }
    /// グラデーション強度（0.0〜1.0）
    var gradientIntensity: Double = 0.4 {
        didSet { saveAppearance() }
    }
    /// 非ホバー時の背景透明度（0.0〜1.0）
    var inactiveOpacity: Double = 0.35 {
        didSet { saveAppearance() }
    }
    /// ホバー時の背景透明度（0.0〜1.0）
    var activeOpacity: Double = 1.0 {
        didSet { saveAppearance() }
    }

    /// ホバー時のバー膨張率（1.0〜2.0）
    var hoverScale: Double = 1.25 {
        didSet { saveAppearance() }
    }

    /// true のとき ウィンドウを持たない常駐アプリ（.regular でウィンドウなし / .accessory）も表示する
    var showResidentApps: Bool = false {
        didSet { saveAppearance() }
    }

    // MARK: - Appearance Persistence

    private static let udKey = "appAppearance_v1"

    private struct StoredAppearance: Codable {
        var barSize: String
        var orientation: String
        var position: String
        var gradientPreset: String
        var gradientIntensity: Double
        var showResidentApps: Bool
        var inactiveOpacity: Double?
        var activeOpacity: Double?
        var hoverScale: Double?
    }

    private func saveAppearance() {
        let stored = StoredAppearance(
            barSize: barSize.rawValue,
            orientation: orientation.rawValue,
            position: position.rawValue,
            gradientPreset: gradientPreset.rawValue,
            gradientIntensity: gradientIntensity,
            showResidentApps: showResidentApps,
            inactiveOpacity: inactiveOpacity,
            activeOpacity: activeOpacity,
            hoverScale: hoverScale
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.udKey)
        }
    }

    private func loadAppearance() {
        guard let data = UserDefaults.standard.data(forKey: Self.udKey),
              let stored = try? JSONDecoder().decode(StoredAppearance.self, from: data) else { return }
        barSize = BarSize(rawValue: stored.barSize) ?? .medium
        orientation = BarOrientation(rawValue: stored.orientation) ?? .horizontal
        position = BarPosition(rawValue: stored.position) ?? .right
        gradientPreset = GradientPreset(rawValue: stored.gradientPreset) ?? .none
        gradientIntensity = stored.gradientIntensity
        showResidentApps = stored.showResidentApps
        inactiveOpacity = stored.inactiveOpacity ?? 0.35
        activeOpacity = stored.activeOpacity ?? 1.0
        hoverScale = stored.hoverScale ?? 1.25
    }

    /// 縦型時のフォルダ最大表示数
    var verticalFolderMaxVisible: Int { 3 }

    var apps: [AppItem] {
        // windowCheckVersion を参照し、ウィンドウ状態が変化した場合のみ再評価される
        _ = appMonitor.windowCheckVersion

        // キャッシュ済みの PID セットを使用（タイマー側で更新済み）
        let windowedPIDs = appMonitor.cachedWindowPIDs

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

    // MARK: - Hotkey Actions

    /// ホットキー（数字キー）でバー左から N 番目のアプリを切り替える
    func activateApp(at index: Int) {
        guard index < apps.count, case .app(let app) = apps[index].kind else { return }
        WindowSwitcher.activateMostRecent(app)
    }

    /// ホットキー（数字キー）でバー左から N 番目のフォルダを切り替える
    func activateFolder(at index: Int) {
        guard index < folders.count, case .folder(let url) = folders[index].kind else { return }
        WindowSwitcher.openFolder(url)
    }

    /// 表示中のアプリ・フォルダ数からパネルサイズを動的計算する
    var panelWidth: CGFloat {
        switch orientation {
        case .horizontal:
            return horizontalPanelWidth
        case .vertical:
            return verticalPanelWidth
        }
    }

    var panelHeight: CGFloat {
        switch orientation {
        case .horizontal:
            return horizontalPanelHeight
        case .vertical:
            return verticalPanelHeight
        }
    }

    // MARK: - Horizontal Layout

    /// ホバー膨張後のアイコンサイズ
    private var hoveredIconSize: CGFloat { iconSize * CGFloat(hoverScale) }

    private var horizontalPanelWidth: CGFloat {
        let maxVisible = 9
        let itemFrameWidth = hoveredIconSize + 4   // 膨張後のサイズで確保
        let spacing: CGFloat = 8
        let rowPadding: CGFloat = 4   // MagnifyingIconRow の edgePadding
        let barPadding: CGFloat = 10  // 膨張時の水平パディング

        func slotCount(_ count: Int) -> Int {
            count > maxVisible ? maxVisible + 1 : count
        }

        func rowWidth(_ count: Int) -> CGFloat {
            let slots = slotCount(count)
            guard slots > 0 else { return 0 }
            return CGFloat(slots) * itemFrameWidth
                + CGFloat(slots - 1) * spacing
                + rowPadding * 2
        }

        // アプリ + セパレータ + フォルダを1行で表示
        var contentWidth = rowWidth(apps.count)
        if !folders.isEmpty {
            contentWidth += 10 + rowWidth(folders.count) // セパレータ + マージン + フォルダ列
        }

        let totalWidth = contentWidth + barPadding * 2
        let maxWidth = NSScreen.main?.visibleFrame.width ?? 1200
        return min(max(totalWidth, 120), maxWidth)
    }

    private var horizontalPanelHeight: CGFloat {
        let hoveredIcon = hoveredIconSize + 4
        let expandedPadding: CGFloat = 16   // 8 * 2（膨張時の上下パディング）
        let labelSpace: CGFloat = 10
        return expandedPadding + hoveredIcon + labelSpace
    }

    // MARK: - Vertical Layout

    private var verticalPanelWidth: CGFloat {
        let itemFrameWidth = hoveredIconSize + 4   // 膨張後のサイズで確保
        let barPadding: CGFloat = 8 * 2   // 膨張時の水平パディング
        return itemFrameWidth + barPadding + 8
    }

    private var verticalPanelHeight: CGFloat {
        let itemFrameHeight = hoveredIconSize + 4  // 膨張後のサイズで確保
        let spacing: CGFloat = 12            // 縦型アイコン間スペース
        let rowPadding: CGFloat = 4          // MagnifyingIconRow の edgePadding
        let barPadding: CGFloat = 10         // 膨張時の垂直パディング

        let appMaxVisible = 9
        let folderMaxVisible = verticalFolderMaxVisible

        let appSlots = min(apps.count, appMaxVisible) + (apps.count > appMaxVisible ? 1 : 0)
        let folderSlots = min(folders.count, folderMaxVisible) + (folders.count > folderMaxVisible ? 1 : 0)
        let divider: CGFloat = folders.isEmpty ? 0 : 9  // セパレータ + マージン

        let totalSlots = appSlots + folderSlots
        guard totalSlots > 0 else { return 120 }

        let contentHeight = CGFloat(totalSlots) * itemFrameHeight
            + CGFloat(max(0, totalSlots - 1)) * spacing
            + divider
            + rowPadding * 2

        let maxHeight = NSScreen.main?.visibleFrame.height ?? 800
        return min(max(contentHeight + barPadding * 2, 120), maxHeight)
    }
}
