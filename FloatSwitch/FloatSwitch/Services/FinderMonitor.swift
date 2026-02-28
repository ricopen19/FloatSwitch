//
//  FinderMonitor.swift
//  FloatSwitch
//

import Foundation
import ScriptingBridge

/// ScriptingBridge + ポーリングで Finder ウィンドウ（フォルダ）をリアルタイム監視する
///
/// - ScriptingBridge が動的生成するクラス (FinderApplication 等) への型キャストは
///   dyld がランタイムにシンボルを解決できずクラッシュするため使用しない。
/// - value(forKey:) による KVC アクセスで同等の機能を実現する。
@Observable
final class FinderMonitor {
    private(set) var folders: [AppItem] = []

    private var timer: Timer?

    init() {
        refresh()
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }

    private func startPolling() {
        // メインスレッドのランループでスケジュール → refresh() もメインスレッドで呼ばれる
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        guard let finder = SBApplication(bundleIdentifier: "com.apple.finder") else { return }

        // FinderWindows: フォルダを表示しているファイルビューアウィンドウ一覧
        // SBElementArray は NSArray サブクラスなので [AnyObject] にキャスト可能
        guard let windows = finder.value(forKey: "FinderWindows") as? [AnyObject] else { return }

        var newFolders: [AppItem] = []
        for window in windows {
            guard let nsWindow = window as? NSObject,
                  let target = nsWindow.value(forKey: "target") as? NSObject,
                  // URL: "file:///Users/foo/Desktop/" 形式の文字列
                  let urlString = target.value(forKey: "URL") as? String,
                  let url = URL(string: urlString) else { continue }
            newFolders.append(AppItem(folderURL: url))
        }

        // 変化があった場合のみ更新（不要な SwiftUI 再描画を防ぐ）
        if newFolders.map(\.id) != folders.map(\.id) {
            folders = newFolders
        }
    }
}
