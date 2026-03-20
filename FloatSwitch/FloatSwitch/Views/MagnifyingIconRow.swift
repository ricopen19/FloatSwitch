//
//  MagnifyingIconRow.swift
//  FloatSwitch
//

import SwiftUI
import UniformTypeIdentifiers

/// Dock 風の hover 拡大エフェクト付きアイコン列
///
/// - 最大 `maxVisibleCount` 個を表示し、超過分は「+N」ボタンでポップオーバー表示
/// - アクティブドット（ウィンドウを持つアプリ）表示
/// - ラベルはアイコン個別ホバー時のみ表示
struct MagnifyingIconRow: View {
    let items: [AppItem]
    let iconSize: CGFloat
    var orientation: BarOrientation = .horizontal
    var showNumbers: Bool = false
    var maxVisibleCount: Int = 9
    var gradientPreset: GradientPreset = .none
    var gradientIntensity: Double = 0.4
    var onTap: (AppItem) -> Void = { _ in }
    var onHide: (AppItem) -> Void = { _ in }
    var onReorder: (String, String) -> Void = { _, _ in }

    @State private var showOverflow = false
    @State private var isPopoverHovered = false
    /// ホバー中のアイテム ID（ラベル表示用）
    // swiftlint:disable implicit_optional_initialization
    @State private var hoveredItemID: String? = nil
    // swiftlint:enable implicit_optional_initialization

    /// アイコン間スペース（縦型は広め）
    private var itemSpacing: CGFloat { isVertical ? 12 : 8 }
    private let edgePadding: CGFloat = 4

    private var itemFrameWidth: CGFloat { iconSize + 4 }

    /// 表示するアイテム（最大 maxVisibleCount）
    private var visibleItems: [AppItem] {
        Array(items.prefix(maxVisibleCount))
    }

    /// オーバーフロー分のアイテム
    private var overflowItems: [AppItem] {
        items.count > maxVisibleCount ? Array(items.dropFirst(maxVisibleCount)) : []
    }

    private var isVertical: Bool { orientation == .vertical }


    var body: some View {
        Group {
            if isVertical {
                verticalBody
            } else {
                horizontalBody
            }
        }
    }

    // MARK: - Horizontal Layout

    private var horizontalBody: some View {
        HStack(alignment: .bottom, spacing: itemSpacing) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                iconView(item: item, index: index)
            }

            if !overflowItems.isEmpty {
                overflowButton
            }
        }
        .padding(.horizontal, edgePadding)
    }

    // MARK: - Vertical Layout

    private var verticalBody: some View {
        VStack(spacing: itemSpacing) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                iconView(item: item, index: index)
            }

            if !overflowItems.isEmpty {
                overflowButton
            }
        }
        .padding(.vertical, edgePadding)
    }

    // MARK: - Overflow

    private var overflowButton: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: iconSize * 0.2)
                    .fill(.thinMaterial)
                    .overlay {
                        if let (start, end) = gradientPreset.colors {
                            RoundedRectangle(cornerRadius: iconSize * 0.2)
                                .fill(
                                    LinearGradient(
                                        colors: [start, end],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .opacity(0.15 + gradientIntensity * 0.7)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: iconSize * 0.2)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    )
                    .frame(width: iconSize, height: iconSize)
                Text("+\(overflowItems.count)")
                    .font(.system(size: iconSize * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text("その他")
                .font(.system(size: max(8, iconSize * 0.28)))
                .lineLimit(1)
                .frame(width: itemFrameWidth)
                .opacity(0) // スペース確保のみ（ホバーなし時は非表示）
        }
        .frame(width: itemFrameWidth, alignment: .center)
        .onHover { hovering in
            if hovering {
                showOverflow = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if !isPopoverHovered { showOverflow = false }
                }
            }
        }
        .onTapGesture { showOverflow.toggle() }
        .popover(isPresented: $showOverflow, arrowEdge: isVertical ? .trailing : .bottom) {
            overflowGrid
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.thinMaterial)
                        .overlay {
                            if let (start, end) = gradientPreset.colors {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        LinearGradient(
                                            colors: [start, end],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .opacity(0.15 + gradientIntensity * 0.7)
                            }
                        }
                }
                .onHover { hovering in
                    isPopoverHovered = hovering
                    if !hovering {
                        showOverflow = false
                    }
                }
        }
    }

    private var overflowGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(iconSize + 20), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(overflowItems) { item in
                VStack(spacing: 3) {
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
                    Text(item.name)
                        .font(.system(size: max(8, iconSize * 0.28)))
                        .lineLimit(1)
                        .frame(width: iconSize + 16)
                }
                .onTapGesture {
                    onTap(item)
                    showOverflow = false
                }
                .contextMenu {
                    if case .app = item.kind {
                        Button("バーから隠す") { onHide(item) }
                    }
                }
            }
        }
        .padding(14)
    }

    // MARK: - Icon View

    private func iconView(item: AppItem, index: Int) -> some View {
        let bundleID: String = {
            if case .app(let app) = item.kind { return app.bundleIdentifier ?? "" }
            return ""
        }()

        let badgeNumber = (showNumbers && index < 9) ? index + 1 : nil
        let isItemHovered = hoveredItemID == item.id

        return iconContent(item: item, badgeNumber: badgeNumber, isItemHovered: isItemHovered)
            .onHover { hovering in
                hoveredItemID = hovering ? item.id : nil
            }
            .contextMenu { windowContextMenu(for: item) }
            .onDrag {
                NSItemProvider(object: bundleID as NSString)
            }
            .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                guard !bundleID.isEmpty else { return false }
                providers.first?.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let fromBundleID = obj as? String,
                          !fromBundleID.isEmpty,
                          fromBundleID != bundleID else { return }
                    DispatchQueue.main.async {
                        onReorder(fromBundleID, bundleID)
                    }
                }
                return true
            }
    }

    /// アイコン + ラベル（横・縦共通: アイコン下にラベル表示）
    private func iconContent(item: AppItem, badgeNumber: Int?, isItemHovered: Bool) -> some View {
        VStack(spacing: 2) {
            iconImage(item: item, badgeNumber: badgeNumber)
                .contentShape(Rectangle())
                .onTapGesture { onTap(item) }
            Text(item.name)
                .font(.system(size: max(8, iconSize * 0.28)))
                .lineLimit(1)
                .frame(width: itemFrameWidth)
                .opacity(isItemHovered ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(width: itemFrameWidth, alignment: .center)
        .animation(.easeOut(duration: 0.12), value: isItemHovered)
    }

    /// アイコン画像 + バッジ番号
    private func iconImage(item: AppItem, badgeNumber: Int?) -> some View {
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
        .overlay(alignment: .topTrailing) {
            if let num = badgeNumber {
                Text("\(num)")
                    .font(.system(size: max(8, iconSize * 0.3), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.secondary, in: RoundedRectangle(cornerRadius: 3))
                    .offset(x: 3, y: -3)
            }
        }
    }

    /// 複数ウィンドウを持つアプリのとき右クリックメニューにウィンドウ一覧を表示する
    @ViewBuilder
    private func windowContextMenu(for item: AppItem) -> some View {
        if case .app(let app) = item.kind {
            let ws = WindowSwitcher.windows(for: app.processIdentifier)
                .filter { !$0.title.isEmpty }
            if ws.count > 1 {
                Text("ウィンドウを選択")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ws) { window in
                    Button {
                        WindowSwitcher.activate(window, app: app)
                    } label: {
                        let label = window.title.isEmpty ? "無題" : window.title
                        if window.isMinimized {
                            Label(label, systemImage: "minus.square")
                        } else {
                            Text(label)
                        }
                    }
                }
                Divider()
            }

            Button("バーから隠す") { onHide(item) }
        }
    }

}
