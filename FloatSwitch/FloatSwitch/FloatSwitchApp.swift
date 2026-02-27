//
//  FloatSwitchApp.swift
//  FloatSwitch
//
//  Created by 土屋良平 on 2026/02/27.
//

import SwiftUI

@main
struct FloatSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // フローティングパネルは AppDelegate で管理するため、通常のウィンドウは持たない
        Settings { EmptyView() }
    }
}
