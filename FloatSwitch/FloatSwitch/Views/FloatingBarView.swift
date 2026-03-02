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
/// - 上段: 起動中アプリ
/// - 下段: Finder フォルダ（存在する場合のみ表示）
/// - 弧状シェイプ + hover 半透明 + 右クリックでサイズ変更
struct FloatingBarView: View {
    var viewModel: AppViewModel

    @State private var isHovered = false

    private let arcDepth: CGFloat = 22

    var body: some View {
        ZStack(alignment: .top) {
            // 弧状バックグラウンド
            FloatingBarShape(cornerRadius: 14, arcDepth: arcDepth)
                .fill(.regularMaterial)

            // コンテンツ（拡大エフェクトが上方にはみ出す余白を確保）
            VStack(spacing: 0) {
                // 拡大エフェクト用の上マージン
                Spacer()
                    .frame(height: viewModel.iconSize * 0.8)

                // 上段: アプリ
                MagnifyingIconRow(items: viewModel.apps, iconSize: viewModel.iconSize) { item in
                    handleTap(item)
                } onHide: { item in
                    if case .app(let app) = item.kind, let bid = app.bundleIdentifier {
                        viewModel.customization.hide(bundleID: bid)
                    }
                } onReorder: { fromBundleID, toBundleID in
                    viewModel.reorderApps(fromBundleID: fromBundleID, toBundleID: toBundleID)
                }

                if !viewModel.folders.isEmpty {
                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)

                    // 下段: Finder フォルダ
                    MagnifyingIconRow(items: viewModel.folders, iconSize: viewModel.iconSize) { item in
                        handleTap(item)
                    }
                }

                // 弧の深さ分のスペーサー
                Spacer()
                    .frame(height: arcDepth + 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isHovered ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu { // バー全体の右クリック（サイズ変更・フィルター設定）
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
                        Button("再表示: \(bid)") {
                            viewModel.customization.show(bundleID: bid)
                        }
                    }
                }
            }

            Divider()

            // --- アクセシビリティ権限（ウィンドウ巡回・一覧表示に必要）---
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
    }

    // MARK: - Private

    private func handleTap(_ item: AppItem) {
        switch item.kind {
        case .app(let app):
            WindowSwitcher.activateMostRecent(app)
        case .folder(let url):
            WindowSwitcher.openFolder(url)
        }
    }
}
