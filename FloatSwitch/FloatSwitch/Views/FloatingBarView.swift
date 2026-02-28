//
//  FloatingBarView.swift
//  FloatSwitch
//
//  Created by 土屋良平 on 2026/02/27.
//

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
                MagnifyingIconRow(items: viewModel.apps, iconSize: viewModel.iconSize)

                if !viewModel.folders.isEmpty {
                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)

                    // 下段: Finder フォルダ
                    MagnifyingIconRow(items: viewModel.folders, iconSize: viewModel.iconSize)
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
        .contextMenu {
            // --- アプリ表示フィルター ---
            Text("表示するアプリ")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                viewModel.showAccessoryApps.toggle()
            } label: {
                if viewModel.showAccessoryApps {
                    Label("ウィンドウ形式 + 常駐アプリ", systemImage: "checkmark")
                } else {
                    Text("ウィンドウ形式 + 常駐アプリ")
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
}
