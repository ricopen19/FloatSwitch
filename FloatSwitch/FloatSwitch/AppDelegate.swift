//
//  AppDelegate.swift
//  FloatSwitch
//
//  Created by 土屋良平 on 2026/02/27.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var floatingPanel: FloatingPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupFloatingPanel()
    }

    private func setupFloatingPanel() {
        floatingPanel = FloatingPanel()
        floatingPanel?.orderFront(nil)
    }
}
