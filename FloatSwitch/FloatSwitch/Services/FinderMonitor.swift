//
//  FinderMonitor.swift
//  FloatSwitch
//

import Foundation

/// ScriptingBridge + ポーリングで Finder ウィンドウ（フォルダ）をリアルタイム監視する
/// - FinderFinderWindow.target.URL でフォルダのフルパスを取得
/// - 2 秒間隔でポーリングし、差分があれば folders を更新
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
        guard let finder = SBApplication(bundleIdentifier: "com.apple.finder") as? FinderApplication else {
            return
        }

        // FinderWindows: フォルダを表示しているファイルビューアウィンドウのみ取得
        // SBElementArray は NSArray のサブクラスなので for-in で要素を取り出す
        var newFolders: [AppItem] = []
        if let windowArray = finder.finderWindows() {
            for item in windowArray {
                guard let window = item as? FinderFinderWindow else { continue }
                // target: ウィンドウが表示しているフォルダ (FinderItem サブクラス)
                // URL: "file:///Users/foo/Desktop/" 形式の文字列
                guard let targetItem = window.target as? FinderItem,
                      let urlString = targetItem.url,
                      let url = URL(string: urlString) else { continue }
                newFolders.append(AppItem(folderURL: url))
            }
        }

        // 変化があった場合のみ更新（不要な SwiftUI 再描画を防ぐ）
        if newFolders.map(\.id) != folders.map(\.id) {
            folders = newFolders
        }
    }
}
