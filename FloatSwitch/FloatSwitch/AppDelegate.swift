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

    /// Accessibility 権限付与を待つタイマー（取得後に無効化）
    private var accessibilityCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let vm = AppViewModel()
        viewModel = vm
        let panel = FloatingPanel(viewModel: vm)
        floatingPanel = panel
        panel.orderFront(nil)

        // Accessibility 権限をリクエスト（ウィンドウ有無の検出に必要）
        requestAccessibilityPermission()

        // barSize / アプリ数 / フォルダ数の変化を監視してパネルをリサイズ
        observeViewModel()
    }

    // MARK: - Private

    /// Accessibility 権限をリクエストし、未付与なら付与後に自動でアプリ一覧を更新する
    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as NSDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            startAccessibilityCheckTimer()
        }
    }

    /// 2 秒ごとに Accessibility 権限を確認し、付与されたらアプリ一覧を再読み込みする
    private func startAccessibilityCheckTimer() {
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            if AXIsProcessTrusted() {
                self?.accessibilityCheckTimer?.invalidate()
                self?.accessibilityCheckTimer = nil
                self?.viewModel?.appMonitor.refreshApps()
            }
        }
    }

    /// panelWidth（アプリ数・barSize に依存）の変化を監視してパネルをリサイズする
    private func observeViewModel() {
        guard let viewModel else { return }
        withObservationTracking {
            _ = viewModel.panelWidth  // apps / folders / barSize / iconSize に依存
            _ = viewModel.barSize     // panelHeight のために別途追跡
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self, let vm = self.viewModel else { return }
                self.floatingPanel?.resize(width: vm.panelWidth, size: vm.barSize)
                self.observeViewModel()
            }
        }
    }
}
