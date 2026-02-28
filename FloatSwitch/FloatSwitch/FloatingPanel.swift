//
//  FloatingPanel.swift
//  FloatSwitch
//
//  Created by 土屋良平 on 2026/02/27.
//

import AppKit
import SwiftUI

/// 常時最前面に表示するフローティングパネル
final class FloatingPanel: NSPanel {
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

        let hostingView = NSHostingView(rootView: FloatingBarView(viewModel: viewModel))
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
        // 現在の右下コーナーを維持
        let newOrigin = CGPoint(
            x: frame.maxX - newSize.width,
            y: frame.minY
        )
        setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: true)
    }

    // MARK: - Private

    private func positionToBottomRight() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame  // Dock・メニューバーを除いた領域
        let windowSize = frame.size
        let margin: CGFloat = 20
        let origin = CGPoint(
            x: screenFrame.maxX - windowSize.width - margin,
            y: screenFrame.minY + margin
        )
        setFrameOrigin(origin)
    }
}
