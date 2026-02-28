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

    /// NSPanel の幅
    var panelWidth: CGFloat {
        switch self {
        case .small:  return 440
        case .medium: return 560
        case .large:  return 720
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

    var apps: [AppItem] {
        let trusted = AXIsProcessTrusted()
        return appMonitor.apps.filter { item in
            guard case .app(let runningApp) = item.kind else { return true }

            // .accessory（常駐型）は toggle でのみ表示
            if runningApp.activationPolicy == .accessory {
                return showResidentApps
            }

            // Accessibility 許可済みの場合: ウィンドウ有無で判定
            if trusted {
                let hasWindows = AppMonitor.hasWindows(pid: runningApp.processIdentifier)
                return hasWindows || showResidentApps
            }

            // Accessibility 未許可の場合: 全 .regular を表示（フォールバック）
            return true
        }
    }

    var folders: [AppItem] { finderMonitor.folders }
    var iconSize: CGFloat { barSize.iconSize }
}
