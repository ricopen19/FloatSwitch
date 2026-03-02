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
/// また `rightMouseDown` をオーバーライドしてコンテキストメニューをバー上端の直上に表示する。
/// バーが Dock 直上に配置されているとき、システムのデフォルト配置ではメニューが
/// Dock の後ろ（不可視領域）に描画されてしまうため、上方向へ強制展開する。
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // isMovableByWindowBackground = true のままだと .onDrag と競合するため、
    // 独自ドラッグ実装に切り替えてウィンドウ移動をここで処理する
    override var mouseDownCanMoveWindow: Bool { false }

    // swiftlint:disable implicit_optional_initialization
    private var dragStartLocation: NSPoint? = nil
    // swiftlint:enable implicit_optional_initialization

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartLocation, let window else {
            super.mouseDragged(with: event)
            return
        }
        // ドラッグ開始点がアイテム（アイコン枠）の上かどうかを確認
        // hitTest でアイコンビュー上なら SwiftUI の .onDrag に任せる
        if let hit = hitTest(convert(start, from: nil)) as? NSHostingView<Content>,
           hit !== self {
            super.mouseDragged(with: event)
            return
        }

        let dragDelta = NSPoint(
            x: event.locationInWindow.x - start.x,
            y: event.locationInWindow.y - start.y
        )
        // ごく小さな動きは誤操作として無視（右クリックの揺れ対策）
        guard abs(dragDelta.x) > 2 || abs(dragDelta.y) > 2 else { return }

        let newOrigin = NSPoint(
            x: window.frame.origin.x + dragDelta.x,
            y: window.frame.origin.y + dragDelta.y
        )
        window.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menu(for: event), !menu.items.isEmpty else {
            super.rightMouseDown(with: event)
            return
        }

        // NSMenu.popUpContextMenu はイベントの座標を元に macOS が適切な位置を計算する。
        // popUp(positioning:at:in:nil) はスクリーン座標の解釈が外部モニターでズレるため、
        // こちらを使うことで全モニターで正しく動作する。
        //
        // ただし Dock 直上にバーがある場合、メニューが Dock の背後に描画されることがある。
        // その対策として synthesizedEvent の locationInWindow を上端座標に差し替えて渡す。
        guard let window else {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }

        let barTopYInWindow = window.frame.height   // ウィンドウ座標系でのバー上端
        let adjustedLocation = NSPoint(x: event.locationInWindow.x, y: barTopYInWindow + 4)

        // CGEvent でウィンドウ座標を差し替えた合成イベントを作る
        if let cgEvent = event.cgEvent?.copy() {
            let screenPoint = window.convertPoint(toScreen: adjustedLocation)
            cgEvent.location = screenPoint
            if let syntheticEvent = NSEvent(cgEvent: cgEvent) {
                NSMenu.popUpContextMenu(menu, with: syntheticEvent, for: self)
                return
            }
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
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

        // ウィンドウ移動は FirstMouseHostingView.mouseDragged で処理する
        isMovableByWindowBackground = false

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

    /// アプリ数変化・barSize 変更時に現在の右端を固定したままパネルをリサイズする
    ///
    /// - 右端（frame.maxX）を変えずに幅を更新することで、アイコン増減時の横ズレを防ぐ
    /// - ユーザーがバーを移動していた場合もその位置を保つ
    /// - 画面外に出そうな場合のみ visibleFrame でクランプする
    func resize(width: CGFloat, size: BarSize) {
        let newSize = CGSize(width: width, height: size.panelHeight)
        let anchor = CGPoint(x: frame.maxX - 1, y: frame.minY + 1)
        let visibleFrame = currentVisibleFrame(anchor: anchor)
        // 右端を現在位置に固定して原点 X を計算（画面外へのはみ出しのみクランプ）
        let preferredOriginX = frame.maxX - newSize.width
        let newOriginX = max(visibleFrame.minX, min(preferredOriginX, visibleFrame.maxX - newSize.width))
        let newOrigin = CGPoint(
            x: newOriginX,
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
