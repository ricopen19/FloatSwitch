//
//  AppCustomization.swift
//  FloatSwitch
//

import AppKit
import Foundation

/// アプリの非表示・表示順序をユーザー設定として管理するクラス
///
/// 設定ファイル: ~/.config/floatswitch/hidden_apps.json
@Observable
final class AppCustomization {

    // MARK: - Config

    struct Config: Codable {
        var hiddenBundleIDs: [String] = []
        var orderedBundleIDs: [String] = []
    }

    // MARK: - Properties

    private(set) var config: Config = Config()

    private let configURL: URL

    // MARK: - Init

    init() {
        let dir = URL.homeDirectory.appending(path: ".config/floatswitch")
        configURL = dir.appending(path: "hidden_apps.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Public

    /// 指定した bundleID のアプリをバーから隠す
    func hide(bundleID: String) {
        guard !config.hiddenBundleIDs.contains(bundleID) else { return }
        config.hiddenBundleIDs.append(bundleID)
        save()
    }

    /// 指定した bundleID のアプリを再表示する
    func show(bundleID: String) {
        config.hiddenBundleIDs.removeAll { $0 == bundleID }
        save()
    }

    /// 表示順序を更新する（バー上でのドラッグ並び替え後に呼ぶ）
    func updateOrder(bundleIDs: [String]) {
        config.orderedBundleIDs = bundleIDs
        save()
    }

    /// bundleID からアプリの表示名を返す
    func displayName(for bundleID: String) -> String {
        // 起動中のアプリから探す
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let name = app.localizedName {
            return name
        }
        // インストール済みアプリのパスから探す
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = bundle.infoDictionary?["CFBundleName"] as? String ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String {
            return name
        }
        return bundleID
    }

    // MARK: - Private

    private func load() {
        guard let data = try? Data(contentsOf: configURL) else { return }
        config = (try? JSONDecoder().decode(Config.self, from: data)) ?? Config()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}
