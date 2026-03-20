//
//  AppDelegate.swift
//  FloatSwitch
//
//  Created by 土屋良平 on 2026/02/27.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var floatingPanel: FloatingPanel?
    private var viewModel: AppViewModel?
    private var hotkeyService: HotkeyService?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ウィンドウ切り替え機能（最小化解除・ウィンドウ一覧取得）に AX 権限が必要
        requestAccessibilityPermissionIfNeeded()

        let vm = AppViewModel()
        viewModel = vm

        let panel = FloatingPanel(viewModel: vm, openSettings: { [weak self] in
            self?.openSettings()
        })
        floatingPanel = panel
        panel.orderFront(nil)

        // ホットキーサービスを起動（AX 権限取得後にリトライする仕組み付き）
        startHotkeyService(viewModel: vm)

        // panelWidth（アプリ数・barSize に依存）の変化を監視してパネルをリサイズ
        observeViewModel()
    }

    // MARK: - Settings

    func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let settings = viewModel?.hotkeySettings else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "FloatSwitch 設定"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, viewModel: viewModel!))
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Hotkey

    /// AX 権限が付与されるまで定期的にイベントタップ作成をリトライする
    ///
    /// AX 権限ダイアログが表示された後、ユーザーが System Settings で許可するまでには
    /// タイムラグがあるため、2 秒間隔で最大 30 回リトライする。
    private func startHotkeyService(viewModel: AppViewModel) {
        let service = HotkeyService(viewModel: viewModel, settings: viewModel.hotkeySettings)
        hotkeyService = service

        // 初回で成功していればリトライ不要
        guard !service.isRunning else { return }

        // AX 権限付与を待ってリトライ
        var retryCount = 0
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            retryCount += 1
            if AXIsProcessTrusted() {
                service.retrySetup()
                if service.isRunning {
                    print("[HotkeyService] AX 権限取得後にイベントタップ作成成功")
                    timer.invalidate()
                    return
                }
            }
            if retryCount >= 30 {
                print("[HotkeyService] リトライ上限到達 — AX 権限を確認してアプリを再起動してください")
                timer.invalidate()
            }
        }
    }

    // MARK: - Private

    /// AX 権限が未取得なら System Settings へのダイアログを表示する
    ///
    /// 権限の有無は `AXIsProcessTrusted()` で毎回判定するため、
    /// 権限付与後の再起動は不要（次回の AX 呼び出し時に自動で有効になる）
    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    /// panelWidth / panelHeight / orientation / position の変化を監視してパネルをリサイズ・再配置する
    private func observeViewModel() {
        guard let viewModel else { return }

        // 変更前の orientation / position を記憶しておく
        let prevOrientation = viewModel.orientation
        let prevPosition = viewModel.position

        withObservationTracking {
            _ = viewModel.panelWidth
            _ = viewModel.panelHeight
            _ = viewModel.barSize
            _ = viewModel.orientation
            _ = viewModel.position
            _ = viewModel.hoverScale
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      let vm = self.viewModel,
                      let panel = self.floatingPanel else { return }

                let newWidth  = vm.panelWidth
                let newHeight = vm.panelHeight

                // orientation / position が変わった場合は再配置
                if vm.orientation != prevOrientation || vm.position != prevPosition {
                    panel.resize(width: newWidth, height: newHeight)
                    panel.reposition()
                } else if abs(panel.frame.width - newWidth) > 0.5
                            || abs(panel.frame.height - newHeight) > 0.5 {
                    panel.resize(width: newWidth, height: newHeight)
                }

                self.observeViewModel()
            }
        }
    }
}
