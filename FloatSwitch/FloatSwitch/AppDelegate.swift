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

        // panelWidth（アプリ数・barSize に依存）の変化を監視してパネルをリサイズ
        observeViewModel()
    }

    // MARK: - Private

    /// panelWidth / barSize の変化を監視してパネルをリサイズする
    ///
    /// - Note: AppMonitor.windowCheckVersion により 0.5 秒ごとに再評価が走るが、
    ///         実際にサイズが変化した場合のみ setFrame を呼ぶ（アニメーション連打を防止）
    private func observeViewModel() {
        guard let viewModel else { return }
        withObservationTracking {
            _ = viewModel.panelWidth  // apps / folders / barSize / windowCheckVersion に依存
            _ = viewModel.barSize     // panelHeight のために別途追跡
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      let vm = self.viewModel,
                      let panel = self.floatingPanel else { return }

                let newWidth  = vm.panelWidth
                let newHeight = vm.barSize.panelHeight

                // サイズが実際に変わった場合のみリサイズ（0.5pt 以内の誤差は無視）
                if abs(panel.frame.width - newWidth) > 0.5
                    || abs(panel.frame.height - newHeight) > 0.5 {
                    panel.resize(width: newWidth, size: vm.barSize)
                }

                self.observeViewModel()
            }
        }
    }
}
