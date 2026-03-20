//
//  FloatingBarShape.swift
//  FloatSwitch
//

import SwiftUI

/// 湾曲ディスプレイ風のフローティングバーシェイプ
///
/// 上辺・下辺ともに ∩ 型カーブ。
/// 上辺は中央が高く端が低い（湾曲ディスプレイの「端が手前に来る」感覚）。
/// 下辺は既存の Dock 風弧を維持。
///
/// ```
///     ╭──────────────────────────╮  ← 上辺 ∩ カーブ
///    ╱                            ╲
///   │    🔵  🟢  🔴  🟡  🟣      │
///    ╲                            ╱
///     ╰──────────────────────────╯  ← 下辺 弧
/// ```
struct FloatingBarShape: Shape {
    var cornerRadius: CGFloat = 14
    /// ∩ カーブの深さ（端が中央より何 pt 低いか、上辺・下辺共通）
    var curveDepth: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 上辺: 端は minY + curveDepth、中央は minY（最も高い）
        let topEdgeY = rect.minY + curveDepth
        // 下辺: 端は maxY - curveDepth、中央は maxY - 2*curveDepth（中央が高い ∩）
        let bottomEdgeY = rect.maxY - curveDepth

        // ── 左上角丸の始点 ──
        path.move(to: CGPoint(x: rect.minX, y: topEdgeY + cornerRadius))

        // 左上角丸
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: topEdgeY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        // ── 上辺 ∩ カーブ ──
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: topEdgeY),
            control: CGPoint(x: rect.midX, y: rect.minY - curveDepth)
        )

        // 右上角丸
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: topEdgeY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )

        // ── 右辺 ──
        path.addLine(to: CGPoint(x: rect.maxX, y: bottomEdgeY - cornerRadius))

        // 右下角丸
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: bottomEdgeY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // ── 下辺 ∩ カーブ（中央が高い = 上に膨らむ）──
        // B(0.5).y = bottomEdgeY - curveDepth とするには ctrl.y = maxY - 3*curveDepth
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: bottomEdgeY),
            control: CGPoint(x: rect.midX, y: rect.maxY - 3 * curveDepth)
        )

        // 左下角丸
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: bottomEdgeY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // ── 左辺（上角丸まで）──
        path.addLine(to: CGPoint(x: rect.minX, y: topEdgeY + cornerRadius))

        path.closeSubpath()
        return path
    }
}
