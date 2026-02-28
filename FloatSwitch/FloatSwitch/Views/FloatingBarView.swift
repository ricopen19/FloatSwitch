//
//  FloatingBarView.swift
//  FloatSwitch
//
//  Created by 土屋良平 on 2026/02/27.
//

import SwiftUI

/// フローティングバーのルートビュー（Phase 3: アプリ・フォルダ一覧表示）
struct FloatingBarView: View {
    var viewModel: AppViewModel
    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)

            HStack(spacing: 0) {
                // 起動中アプリ
                appRow

                if !viewModel.folders.isEmpty {
                    Divider()
                        .padding(.vertical, 8)

                    // Finder フォルダ
                    folderRow
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isHovered ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Subviews

    private var appRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.apps) { item in
                    itemView(for: item)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var folderRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.folders) { item in
                    itemView(for: item)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func itemView(for item: AppItem) -> some View {
        VStack(spacing: 2) {
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 32, height: 32)
            }
            Text(item.name)
                .font(.system(size: 9))
                .lineLimit(1)
                .frame(width: 44)
        }
        .frame(width: 48)
    }
}
