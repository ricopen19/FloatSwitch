//
//  HotkeySettings.swift
//  FloatSwitch
//

import AppKit

// MARK: - HotkeyModifier

/// 数字キー（1〜9）と組み合わせる修飾キーのプリセット
///
/// `.disabled` のとき、そのホットキーは無効（グローバル監視に登録しない）。
/// アプリ用とフォルダ用で別々に設定する。
enum HotkeyModifier: String, CaseIterable, Codable {
    case disabled
    case cmdOpt
    case ctrlOpt
    case cmdCtrl
    case cmdOptCtrl
    case cmdShift

    var label: String {
        switch self {
        case .disabled:   return "なし（無効）"
        case .cmdOpt:     return "⌘⌥ + 数字"
        case .ctrlOpt:    return "⌃⌥ + 数字"
        case .cmdCtrl:    return "⌘⌃ + 数字"
        case .cmdOptCtrl: return "⌘⌥⌃ + 数字"
        case .cmdShift:   return "⌘⇧ + 数字"
        }
    }

    /// 比較に使う修飾フラグ。`.disabled` は `nil` を返す。
    var flags: NSEvent.ModifierFlags? {
        switch self {
        case .disabled:   return nil
        case .cmdOpt:     return [.command, .option]
        case .ctrlOpt:    return [.control, .option]
        case .cmdCtrl:    return [.command, .control]
        case .cmdOptCtrl: return [.command, .option, .control]
        case .cmdShift:   return [.command, .shift]
        }
    }
}

// MARK: - HotkeySettings

/// ホットキー設定を UserDefaults に永続化するモデル
@Observable
final class HotkeySettings {
    private static let udKey = "hotkeySettings_v1"

    var appModifier: HotkeyModifier = .disabled {
        didSet { save() }
    }
    var folderModifier: HotkeyModifier = .disabled {
        didSet { save() }
    }

    init() {
        load()
    }

    // MARK: - Private

    private struct Stored: Codable {
        var appModifier: HotkeyModifier
        var folderModifier: HotkeyModifier
    }

    private func save() {
        let stored = Stored(appModifier: appModifier, folderModifier: folderModifier)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.udKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.udKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        appModifier = stored.appModifier
        folderModifier = stored.folderModifier
    }
}
