//
//  AppDelegate.swift
//  FloatSwitch
//
//  Created by 土屋良平 on 2026/02/27.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var floatingPanel: FloatingPanel?
    private var viewModel: AppViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let vm = AppViewModel()
        viewModel = vm
        floatingPanel = FloatingPanel(viewModel: vm)
        floatingPanel?.orderFront(nil)
    }
}
