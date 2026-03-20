//
//  FloatingBarView.swift
//  FloatSwitch
//
//  Created by 土屋良平 on 2026/02/27.
//

import AppKit
import SwiftUI

/// フローティングバーのルートビュー
///
/// Glass Island デザイン:
/// - ガラス質 pill 形状（強角丸 + 上辺ハイライト）
/// - ホバーでスプリング膨張アニメーション
/// - アクティブドット（ウィンドウ状態の可視化）
/// - 横型: アプリ｜セパレータ｜フォルダの1行レイアウト
/// - 縦型: 同じガラス質感を縦方向に展開
struct FloatingBarView: View {
    var viewModel: AppViewModel
    var openSettings: (() -> Void)?

    @State private var isHovered = false

    private let glassCornerRadius: CGFloat = 14

    private var isVertical: Bool { viewModel.orientation == .vertical }

    /// 非ホバー時はベースサイズ、ホバーで膨張
    private var effectiveIconSize: CGFloat {
        isHovered ? viewModel.iconSize * CGFloat(viewModel.hoverScale) : viewModel.iconSize
    }

    var body: some View {
        Group {
            if isVertical {
                verticalContent
            } else {
                horizontalContent
            }
        }
        .padding(.horizontal, isVertical ? (isHovered ? 8 : 4) : (isHovered ? 10 : 4))
        .padding(.vertical, isVertical ? (isHovered ? 10 : 4) : (isHovered ? 8 : 4))
        .background { glassBackground }
        .shadow(
            color: .black.opacity(0.3),
            radius: isHovered ? 16 : 10,
            y: isVertical ? 0 : (isHovered ? 6 : 3)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHovered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { updatePanelAlpha(animated: false) }
        .onChange(of: isHovered) { updatePanelAlpha() }
        .onChange(of: viewModel.activeOpacity) { updatePanelAlpha() }
        .onChange(of: viewModel.inactiveOpacity) { updatePanelAlpha() }
        .contextMenu { contextMenuContent }
    }

    // MARK: - Glass Background

    @ViewBuilder
    private var glassBackground: some View {
        ZStack {
            // Material ベース
            // 非ホバー時は alphaValue で全体制御、ホバー時は activeOpacity で背景のみ制御
            RoundedRectangle(cornerRadius: glassCornerRadius)
                .fill(.thinMaterial)
                .opacity(isHovered ? viewModel.activeOpacity : 1.0)
                .saturation(isHovered ? 1.0 : 0.3)
                .brightness(isHovered ? 0.0 : 0.05)

            // くすみオーバーレイ（非ホバー時に暗くして深みを出す）
            RoundedRectangle(cornerRadius: glassCornerRadius)
                .fill(Color.black.opacity(0.25))
                .opacity(isHovered ? 0.0 : 1.0)

            // インナーシャドウ（深みを追加）
            RoundedRectangle(cornerRadius: glassCornerRadius)
                .strokeBorder(Color.black.opacity(0.3), lineWidth: 4)
                .blur(radius: 4)
                .clipShape(RoundedRectangle(cornerRadius: glassCornerRadius))
                .opacity(isHovered ? 0.3 : 0.5)

            // ガラスの光沢（静的 — CPU 負荷なし）
            glassSheen

            // ボーダーハイライト
            RoundedRectangle(cornerRadius: glassCornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isHovered ? 0.22 : 0.10),
                            .white.opacity(0.02)
                        ],
                        startPoint: isVertical ? .leading : .top,
                        endPoint: isVertical ? .trailing : .bottom
                    ),
                    lineWidth: 1
                )

            // グラデーションオーバーレイ（ホバー時）
            if let (start, end) = viewModel.gradientPreset.colors {
                RoundedRectangle(cornerRadius: glassCornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [start, end],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(isHovered ? 0.15 + viewModel.gradientIntensity * 0.7 : 0.0)
            }
        }
    }

    /// ガラス上辺（横型）or 左辺（縦型）のハイライト光沢
    @ViewBuilder
    private var glassSheen: some View {
        if isVertical {
            LinearGradient(
                colors: [.white.opacity(0.12), .clear],
                startPoint: .leading,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: glassCornerRadius))
            .allowsHitTesting(false)
        } else {
            LinearGradient(
                colors: [.white.opacity(0.15), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: glassCornerRadius))
            .allowsHitTesting(false)
        }
    }

    // MARK: - Horizontal Content

    private var horizontalContent: some View {
        HStack(spacing: 0) {
            // アプリ
            MagnifyingIconRow(
                items: viewModel.apps,
                iconSize: effectiveIconSize,
                orientation: .horizontal,
                showNumbers: viewModel.hotkeySettings.appModifier != .disabled,
                gradientPreset: viewModel.gradientPreset,
                gradientIntensity: viewModel.gradientIntensity,
            ) { item in
                handleTap(item)
            } onHide: { item in
                if case .app(let app) = item.kind, let bid = app.bundleIdentifier {
                    viewModel.customization.hide(bundleID: bid)
                }
            } onReorder: { fromBundleID, toBundleID in
                viewModel.reorderApps(fromBundleID: fromBundleID, toBundleID: toBundleID)
            }

            if !viewModel.folders.isEmpty {
                // 縦線セパレータ
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)

                // フォルダ
                MagnifyingIconRow(
                    items: viewModel.folders,
                    iconSize: effectiveIconSize,
                    orientation: .horizontal,
                    showNumbers: viewModel.hotkeySettings.folderModifier != .disabled,
                    gradientPreset: viewModel.gradientPreset,
                    gradientIntensity: viewModel.gradientIntensity,
                    ) { item in
                    handleTap(item)
                }
            }
        }
    }

    // MARK: - Vertical Content

    private var verticalContent: some View {
        VStack(spacing: 0) {
            // アプリ
            MagnifyingIconRow(
                items: viewModel.apps,
                iconSize: effectiveIconSize,
                orientation: .vertical,
                showNumbers: viewModel.hotkeySettings.appModifier != .disabled,
                gradientPreset: viewModel.gradientPreset,
                gradientIntensity: viewModel.gradientIntensity,
            ) { item in
                handleTap(item)
            } onHide: { item in
                if case .app(let app) = item.kind, let bid = app.bundleIdentifier {
                    viewModel.customization.hide(bundleID: bid)
                }
            } onReorder: { fromBundleID, toBundleID in
                viewModel.reorderApps(fromBundleID: fromBundleID, toBundleID: toBundleID)
            }

            if !viewModel.folders.isEmpty {
                // 横線セパレータ
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)

                // フォルダ（最大3個）
                MagnifyingIconRow(
                    items: viewModel.folders,
                    iconSize: effectiveIconSize,
                    orientation: .vertical,
                    showNumbers: viewModel.hotkeySettings.folderModifier != .disabled,
                    maxVisibleCount: viewModel.verticalFolderMaxVisible,
                    gradientPreset: viewModel.gradientPreset,
                    gradientIntensity: viewModel.gradientIntensity,
                    ) { item in
                    handleTap(item)
                }
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        // --- アプリ表示フィルター ---
        Text("表示するアプリ")
            .font(.caption)
            .foregroundStyle(.secondary)
        Button {
            viewModel.showResidentApps.toggle()
        } label: {
            if viewModel.showResidentApps {
                Label("常駐アプリを表示", systemImage: "checkmark")
            } else {
                Text("常駐アプリを表示")
            }
        }

        if !viewModel.customization.config.hiddenBundleIDs.isEmpty {
            Menu("隠したアプリを管理...") {
                ForEach(viewModel.customization.config.hiddenBundleIDs, id: \.self) { bid in
                    Button("再表示: \(viewModel.customization.displayName(for: bid))") {
                        viewModel.customization.show(bundleID: bid)
                    }
                }
            }
        }

        Divider()

        // --- アクセシビリティ権限 ---
        if AXIsProcessTrusted() {
            Label("アクセシビリティ: 許可済み", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        } else {
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("アクセシビリティを許可する…", systemImage: "exclamationmark.triangle.fill")
            }
        }

        Divider()

        // --- 設定 ---
        Button("設定...") {
            openSettings?()
        }

        Divider()

        // --- バーの向き ---
        Text("バーの向き")
            .font(.caption)
            .foregroundStyle(.secondary)
        ForEach(BarOrientation.allCases, id: \.self) { orient in
            Button {
                viewModel.orientation = orient
            } label: {
                if viewModel.orientation == orient {
                    Label(orient.rawValue, systemImage: "checkmark")
                } else {
                    Text(orient.rawValue)
                }
            }
        }

        // 縦型の場合: 配置位置
        if viewModel.orientation == .vertical {
            Text("配置位置")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(BarPosition.allCases, id: \.self) { pos in
                Button {
                    viewModel.position = pos
                } label: {
                    if viewModel.position == pos {
                        Label(pos.rawValue, systemImage: "checkmark")
                    } else {
                        Text(pos.rawValue)
                    }
                }
            }
        }

        Divider()

        // --- バーのサイズ ---
        Text("バーのサイズ")
            .font(.caption)
            .foregroundStyle(.secondary)
        ForEach(BarSize.allCases, id: \.self) { size in
            Button {
                viewModel.barSize = size
            } label: {
                if viewModel.barSize == size {
                    Label(size.rawValue, systemImage: "checkmark")
                } else {
                    Text(size.rawValue)
                }
            }
        }
    }

    // MARK: - Private

    /// NSPanel.alphaValue で全体透明度を制御
    ///
    /// - 非ホバー: alphaValue = inactiveOpacity（material 含め全体が均一にフェード）
    /// - ホバー: alphaValue = 1.0（アイコンは常に 100%、背景は SwiftUI 側で activeOpacity 制御）
    private func updatePanelAlpha(animated: Bool = true) {
        guard let panel = NSApp.windows.compactMap({ $0 as? FloatingPanel }).first else { return }
        let targetAlpha = CGFloat(isHovered ? 1.0 : viewModel.inactiveOpacity)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = targetAlpha
            }
        } else {
            panel.alphaValue = targetAlpha
        }
    }

    private func handleTap(_ item: AppItem) {
        switch item.kind {
        case .app(let app):
            WindowSwitcher.activateMostRecent(app)
        case .folder(let url):
            WindowSwitcher.openFolder(url)
        }
    }
}
