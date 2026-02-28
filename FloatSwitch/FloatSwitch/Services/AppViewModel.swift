//
//  AppViewModel.swift
//  FloatSwitch
//

import Foundation

/// AppMonitor と FinderMonitor を束ねる状態管理クラス
@Observable
final class AppViewModel {
    let appMonitor = AppMonitor()
    let finderMonitor = FinderMonitor()

    var apps: [AppItem] { appMonitor.apps }
    var folders: [AppItem] { finderMonitor.folders }
}
