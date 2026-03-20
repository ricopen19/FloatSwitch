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
///
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // isMovableByWindowBackground = true のままだと .onDrag と競合するため、
    // 独自ドラッグ実装に切り替えてウィンドウ移動をここで処理する
    override var mouseDownCanMoveWindow: Bool { false }

    // swiftlint:disable implicit_optional_initialization
    private var dragStartLocation: NSPoint? = nil
    // swiftlint:enable implicit_optional_initialization
    /// SwiftUI の .onDrag セッション中かどうか
    private var itemDragActive = false
    /// ウィンドウドラッグモードに入ったかどうか
    private var windowDragActive = false

    /// SwiftUI の .onDrag が開始されたことを検知してフラグを立てる
    override func beginDraggingSession(
        with items: [NSDraggingItem],
        event: NSEvent,
        source: any NSDraggingSource
    ) -> NSDraggingSession {
        itemDragActive = true
        return super.beginDraggingSession(with: items, event: event, source: source)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        // ウィンドウドラッグ確定後は SwiftUI にイベントを渡さない（ホバー誤判定防止）
        if windowDragActive {
            guard let start = dragStartLocation, let window else { return }
            let newOrigin = NSPoint(
                x: window.frame.origin.x + (event.locationInWindow.x - start.x),
                y: window.frame.origin.y + (event.locationInWindow.y - start.y)
            )
            window.setFrameOrigin(newOrigin)
            return
        }

        // アイテムドラッグ中は SwiftUI に任せる
        if itemDragActive {
            super.mouseDragged(with: event)
            return
        }

        // まだどちらか未確定 — SwiftUI にイベントを渡して .onDrag の起動を待つ
        super.mouseDragged(with: event)

        // .onDrag が起動したならウィンドウ移動しない
        guard !itemDragActive else { return }

        // 閾値を超えたらウィンドウドラッグモードに確定
        guard let start = dragStartLocation, let window else { return }
        let dragDelta = NSPoint(
            x: event.locationInWindow.x - start.x,
            y: event.locationInWindow.y - start.y
        )
        guard abs(dragDelta.x) > 4 || abs(dragDelta.y) > 4 else { return }

        windowDragActive = true
        let newOrigin = NSPoint(
            x: window.frame.origin.x + dragDelta.x,
            y: window.frame.origin.y + dragDelta.y
        )
        window.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        itemDragActive = false
        windowDragActive = false
        super.mouseUp(with: event)
    }

}

// MARK: - FloatingPanel

/// 常時最前面に表示するフローティングパネル
final class FloatingPanel: NSPanel {
    private let edgeMargin: CGFloat = 20

    private let viewModel: AppViewModel

    init(viewModel: AppViewModel, openSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        let initialWidth = viewModel.panelWidth
        let initialHeight = viewModel.panelHeight
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        // 常時最前面・全 Space・フルスクリーンでも表示
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // ウィンドウ移動は FirstMouseHostingView.mouseDragged で処理する
        isMovableByWindowBackground = false

        // 透明背景（SwiftUI の material が透過するために必要）
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // 初期透明度（非ホバー状態）
        alphaValue = CGFloat(viewModel.inactiveOpacity)

        let hostingView = FirstMouseHostingView(
            rootView: FloatingBarView(viewModel: viewModel, openSettings: openSettings)
        )
        // SwiftUI の intrinsic サイズによるパネル自動拡縮を無効化（動的リサイズは AppDelegate が管理）
        hostingView.sizingOptions = []
        self.contentView = hostingView

        positionInitial()
    }

    // フローティングパネルはキーウィンドウになれる（ホットキー受付のため）
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// アプリ数変化・barSize/orientation 変更時にパネルをリサイズする
    func resize(width: CGFloat, height: CGFloat) {
        let newSize = CGSize(width: width, height: height)
        // サイズが変わらない場合はスキップ（並び替え時の不要なアニメーション防止）
        guard abs(frame.width - newSize.width) > 0.5
           || abs(frame.height - newSize.height) > 0.5 else { return }
        let anchor = CGPoint(x: frame.maxX - 1, y: frame.minY + 1)
        let visibleFrame = currentVisibleFrame(anchor: anchor)

        let newOrigin: CGPoint
        if viewModel.orientation == .vertical {
            // 縦型: 上端を固定
            let preferredOriginY = frame.maxY - newSize.height
            let clampedY = max(visibleFrame.minY + edgeMargin,
                               min(preferredOriginY, visibleFrame.maxY - newSize.height))
            newOrigin = CGPoint(x: frame.origin.x, y: clampedY)
        } else {
            // 横型: 右端を固定
            let preferredOriginX = frame.maxX - newSize.width
            let newOriginX = max(visibleFrame.minX,
                                 min(preferredOriginX, visibleFrame.maxX - newSize.width))
            // 高さが変わっていなければ y を保持（並び替え時の微妙なズレ防止）
            let newY = abs(newSize.height - frame.height) > 0.5
                ? max(frame.minY, visibleFrame.minY + edgeMargin)
                : frame.origin.y
            newOrigin = CGPoint(x: newOriginX, y: newY)
        }
        // 小さなサイズ変化はアニメーションなし（ジャンプ防止）
        let sizeDiff = abs(frame.width - newSize.width) + abs(frame.height - newSize.height)
        setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: sizeDiff > 20)
    }

    /// orientation / position 変更時に画面端へ再配置する
    func reposition() {
        positionInitial()
    }

    // MARK: - Private

    private func positionInitial() {
        let screenFrame = currentVisibleFrame(anchor: nil)
        let windowSize = frame.size

        let origin: CGPoint
        switch viewModel.orientation {
        case .horizontal:
            // 横型: 右下
            origin = CGPoint(
                x: screenFrame.maxX - windowSize.width - edgeMargin,
                y: screenFrame.minY + edgeMargin
            )
        case .vertical:
            // 縦型: 左 or 右の画面端、垂直中央
            let centerY = screenFrame.midY - windowSize.height / 2
            if viewModel.position == .left {
                origin = CGPoint(x: screenFrame.minX + edgeMargin, y: centerY)
            } else {
                origin = CGPoint(x: screenFrame.maxX - windowSize.width - edgeMargin, y: centerY)
            }
        }
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
