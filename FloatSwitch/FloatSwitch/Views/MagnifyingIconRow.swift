//
//  MagnifyingIconRow.swift
//  FloatSwitch
//

import SwiftUI

/// Dock 風の hover 拡大エフェクト付きアイコン列
///
/// - `onContinuousHover` でマウス X 座標を取得
/// - 各アイテムのレイアウトフレームは固定（HStack が揺れない）
/// - `scaleEffect(anchor: .bottom)` でアイコンが上方向に拡大
struct MagnifyingIconRow: View {
    let items: [AppItem]
    let iconSize: CGFloat

    @State private var hoverX: CGFloat? = nil

    private let itemSpacing: CGFloat = 6
    private let horizontalPadding: CGFloat = 8
    private let maxScale: CGFloat = 1.8

    // HStack 内の各アイテムが占める固定フレーム幅
    private var itemFrameWidth: CGFloat { iconSize + 16 }

    // ホバー効果が届く距離（px）
    private var effectRadius: CGFloat { iconSize * 2.8 }

    var body: some View {
        HStack(alignment: .bottom, spacing: itemSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                iconView(item: item, scale: magnification(for: index))
            }
        }
        .padding(.horizontal, horizontalPadding)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverX = location.x
            case .ended:
                hoverX = nil
            }
        }
        .animation(.spring(duration: 0.18, bounce: 0.2), value: hoverX)
    }

    // MARK: - Private

    private func iconView(item: AppItem, scale: CGFloat) -> some View {
        VStack(spacing: 2) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: iconSize, height: iconSize)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: iconSize * 0.7))
                        .frame(width: iconSize, height: iconSize)
                }
            }
            Text(item.name)
                .font(.system(size: max(8, iconSize * 0.28)))
                .lineLimit(1)
                .frame(width: itemFrameWidth)
        }
        // レイアウトフレームは固定（scaleEffect は視覚のみ、layout に影響しない）
        .frame(width: itemFrameWidth, alignment: .center)
        .scaleEffect(scale, anchor: .bottom)
    }

    /// index 番目のアイテムの拡大率を返す（距離に応じた二次減衰）
    private func magnification(for index: Int) -> CGFloat {
        guard let hoverX else { return 1.0 }
        // 各アイテムの中心 X（固定フレーム幅 + spacing ベース）
        let itemCenterX = horizontalPadding
            + CGFloat(index) * (itemFrameWidth + itemSpacing)
            + itemFrameWidth / 2
        let distance = abs(hoverX - itemCenterX)
        guard distance < effectRadius else { return 1.0 }
        let factor = 1.0 - distance / effectRadius
        // 二次減衰で Dock 風の滑らかな拡大曲線を再現
        return 1.0 + (maxScale - 1.0) * factor * factor
    }
}
