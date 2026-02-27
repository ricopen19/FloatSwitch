//
//  FloatingBarView.swift
//  FloatSwitch
//
//  Created by 土屋良平 on 2026/02/27.
//

import SwiftUI

/// フローティングバーのルートビュー（Phase 2 プレースホルダー）
struct FloatingBarView: View {
    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)

            Text("FloatSwitch")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isHovered ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    FloatingBarView()
        .frame(width: 400, height: 80)
}
