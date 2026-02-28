//
//  FloatingBarShape.swift
//  FloatSwitch
//

import SwiftUI

/// バー下部が湾曲した弧状シェイプ（Dock 風）
///
/// ```
/// ┌──────────────────────────┐
/// │                          │
/// │                          │
/// ╰──────────────────────────╯  ← 中央が最も低い convex 弧
/// ```
struct FloatingBarShape: Shape {
    var cornerRadius: CGFloat = 14
    /// 弧の深さ: 両端から中央に向けて何 pt 下がるか（大きいほど Dock 風）
    var arcDepth: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 左上角丸の始点
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))

        // 上辺
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))

        // 右上角丸
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // 右辺（弧の起点まで）
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - arcDepth))

        // 下部の弧: 両端 (maxY - arcDepth) から中央 (maxY) へ凸状に下がる → ╰──╯
        //
        // 二次ベジェの性質: 曲線の中点 t=0.5 の Y 座標 = 0.5*(端点Y) + 0.5*(制御点Y)
        //   ∴ 中点を maxY にするには 制御点Y = maxY + arcDepth が必要
        //   制御点はパネル外 (maxY+arcDepth) だが、曲線自体はパネル内に収まる
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - arcDepth),
            control: CGPoint(x: rect.midX, y: rect.maxY + arcDepth)
        )

        // 左辺（上角丸まで）
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))

        // 左上角丸
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(-90),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}
