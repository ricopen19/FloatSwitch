//
//  FloatingPanel.swift
//  FloatSwitch
//
//  Created by 土屋良平 on 2026/02/27.
//

import AppKit
import SwiftUI

// MARK: - FirstMouseHostingView

/// 最初のクリックをタップジェスチャとして即座に処理するホスティングビュー
///
/// デフォルトの `NSHostingView` は `acceptsFirstMouse` が false のため、
/// パネルが非アクティブな状態での最初のクリックがウィンドウ活性化に消費される。
/// これにより「1クリックでアクティブ → 2クリック目でスイッチ」という2クリック問題が発生する。
/// `acceptsFirstMouse` を true にすることで初回クリックもジェスチャとして通す。
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - FloatingPanel

/// 常時最前面に表示するフローティングパネル
final class FloatingPanel: NSPanel {
    private let edgeMargin: CGFloat = 20

    init(viewModel: AppViewModel) {
        let initialWidth = viewModel.panelWidth
        let initialHeight = viewModel.barSize.panelHeight
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        // 常時最前面・全 Space・フルスクリーンでも表示
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // バー背景をドラッグして移動可能
        isMovableByWindowBackground = true

        // 透明背景（SwiftUI の material が透過するために必要）
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        let hostingView = FirstMouseHostingView(rootView: FloatingBarView(viewModel: viewModel))
        // SwiftUI の intrinsic サイズによるパネル自動拡縮を無効化（動的リサイズは AppDelegate が管理）
        hostingView.sizingOptions = []
        self.contentView = hostingView

        positionToBottomRight()
    }

    // フローティングパネルはキーウィンドウになれる（ホットキー受付のため）
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// アプリ数変化・barSize 変更時に右下コーナーを固定したままパネルをリサイズする
    func resize(width: CGFloat, size: BarSize) {
        let newSize = CGSize(width: width, height: size.panelHeight)
        // 現在の右下アンカーが属する画面を優先し、マルチディスプレイでの右ズレを抑える
        let anchor = CGPoint(x: frame.maxX - 1, y: frame.minY + 1)
        let visibleFrame = currentVisibleFrame(anchor: anchor)
        let newOrigin = CGPoint(
            x: visibleFrame.maxX - newSize.width - edgeMargin,
            y: max(frame.minY, visibleFrame.minY + edgeMargin)
        )
        setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: true)
    }

    // MARK: - Private

    private func positionToBottomRight() {
        let screenFrame = currentVisibleFrame(anchor: nil)  // Dock・メニューバーを除いた領域
        let windowSize = frame.size
        let origin = CGPoint(
            x: screenFrame.maxX - windowSize.width - edgeMargin,
            y: screenFrame.minY + edgeMargin
        )
        setFrameOrigin(origin)
    }

    private func currentVisibleFrame(anchor: CGPoint?) -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main?.visibleFrame ?? .zero }

        if let anchor,
           let screen = screens.first(where: { $0.frame.contains(anchor) }) {
            return screen.visibleFrame
        }

        if let main = NSScreen.main {
            return main.visibleFrame
        }

        return screens[0].visibleFrame
    }
}
