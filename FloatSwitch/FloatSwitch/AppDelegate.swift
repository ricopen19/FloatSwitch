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
        let panel = FloatingPanel(viewModel: vm)
        floatingPanel = panel
        panel.orderFront(nil)

        // barSize の変更を監視してパネルをリサイズ
        observeBarSize()
    }

    // MARK: - Private

    private func observeBarSize() {
        guard let viewModel else { return }
        withObservationTracking {
            _ = viewModel.barSize
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self, let vm = self.viewModel else { return }
                self.floatingPanel?.resize(to: vm.barSize)
                // 変更を継続して追跡
                self.observeBarSize()
            }
        }
    }
}
