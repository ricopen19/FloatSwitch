//
//  SettingsView.swift
//  FloatSwitch
//

import SwiftUI

/// ホットキー設定画面
///
/// 右クリックメニューの「設定...」から開く NSWindow に埋め込む。
/// アプリ切り替えとフォルダ切り替えの修飾キーをそれぞれ選択できる。
struct SettingsView: View {
    @Bindable var settings: HotkeySettings
    var viewModel: AppViewModel

    var body: some View {
        Form {
            Section {
                Picker("ホバー時グラデーション", selection: Binding(
                    get: { viewModel.gradientPreset },
                    set: { viewModel.gradientPreset = $0 }
                )) {
                    ForEach(GradientPreset.allCases) { preset in
                        Label {
                            Text(preset.rawValue)
                        } icon: {
                            if let color = preset.previewColor {
                                Circle()
                                    .fill(color.gradient)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "circle.dashed")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(preset)
                    }
                }
                if viewModel.gradientPreset != .none {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("強度")
                            Spacer()
                            Text("\(Int(viewModel.gradientIntensity * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { viewModel.gradientIntensity },
                                set: { viewModel.gradientIntensity = $0 }
                            ),
                            in: 0...1,
                            step: 0.05
                        )
                    }
                }
                Text("マウスオーバー時にバー背景にグラデーションを表示します")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("ホバー膨張率")
                        Spacer()
                        Text("×\(String(format: "%.2f", viewModel.hoverScale))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { viewModel.hoverScale },
                            set: { viewModel.hoverScale = $0 }
                        ),
                        in: 1.0...2.0,
                        step: 0.05
                    )
                }
                Text("マウスオーバー時のバー膨張率（×1.0 = 膨張なし）")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("ホバー時の透明度")
                        Spacer()
                        Text("\(Int(viewModel.activeOpacity * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { viewModel.activeOpacity },
                            set: { viewModel.activeOpacity = $0 }
                        ),
                        in: 0.05...1.0,
                        step: 0.05
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("非ホバー時の透明度")
                        Spacer()
                        Text("\(Int(viewModel.inactiveOpacity * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { viewModel.inactiveOpacity },
                            set: { viewModel.inactiveOpacity = $0 }
                        ),
                        in: 0.05...1.0,
                        step: 0.05
                    )
                }
            } header: {
                Text("外観")
            }

            Section {
                Picker("アプリ切り替え", selection: $settings.appModifier) {
                    ForEach(HotkeyModifier.allCases, id: \.self) { mod in
                        Text(mod.label).tag(mod)
                    }
                }
                Text("バー左端から順に 1〜9 番に対応します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("ホットキー")
            }

            Section {
                Picker("フォルダ切り替え", selection: $settings.folderModifier) {
                    ForEach(HotkeyModifier.allCases, id: \.self) { mod in
                        Text(mod.label).tag(mod)
                    }
                }
                Text("バー左端から順に 1〜9 番に対応します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if settings.appModifier != .disabled {
                    LabeledContent("アプリ例") {
                        Text(modifierExampleText(settings.appModifier))
                            .foregroundStyle(.secondary)
                    }
                }
                if settings.folderModifier != .disabled {
                    LabeledContent("フォルダ例") {
                        Text(modifierExampleText(settings.folderModifier))
                            .foregroundStyle(.secondary)
                    }
                }
                if settings.appModifier == .disabled && settings.folderModifier == .disabled {
                    Text("ホットキーはすべて無効です")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("設定中のキー")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 400)
    }

    // MARK: - Private

    private func modifierExampleText(_ modifier: HotkeyModifier) -> String {
        let prefix = modifier.label.replacingOccurrences(of: " + 数字", with: "")
        return "\(prefix)1 〜 \(prefix)9"
    }
}
