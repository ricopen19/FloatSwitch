//
//  HotkeyService.swift
//  FloatSwitch
//

import AppKit

/// グローバルホットキーを監視してアプリ・フォルダを切り替えるサービス
///
/// ## 設計
/// - `CGEvent.tapCreate` で Quartz レベルのイベントタップを作成し、全キー入力を観察
/// - 数字キー 1〜9 が押されたとき、修飾フラグを `HotkeySettings` と照合してアクション実行
/// - キーコードで判定するためキーボードレイアウト非依存
/// - 設定変更（`HotkeySettings` の変更）は次回キー入力から即座に反映される（参照渡しのため）
///
/// ## 権限
/// - Accessibility (AX) 権限が必要（Input Monitoring は不要）
/// - AX 権限がない場合はイベントタップの作成に失敗し、ログを出力する
final class HotkeyService {

    // MARK: - Constants

    /// キーボード上段の数字キー 1〜9 に対応するキーコード（レイアウト非依存）
    private static let numberKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
        22: 6, 26: 7, 28: 8, 25: 9
    ]

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private weak var viewModel: AppViewModel?
    private let settings: HotkeySettings

    /// イベントタップが稼働中かどうか
    var isRunning: Bool { eventTap != nil }

    // MARK: - Init

    init(viewModel: AppViewModel, settings: HotkeySettings) {
        self.viewModel = viewModel
        self.settings = settings
        setupEventTap()
    }

    deinit { tearDownEventTap() }

    /// AX 権限取得後にイベントタップの作成を再試行する
    func retrySetup() {
        guard eventTap == nil else { return }
        setupEventTap()
    }

    // MARK: - Private

    private func setupEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        // userInfo で self を渡してコールバックからアクセスする
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,   // イベントを横取りしない（観察のみ）
            eventsOfInterest: CGEventMask(eventMask),
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ) else {
            print("[HotkeyService] event tap 作成失敗（AX 権限を確認してください）")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[HotkeyService] event tap 作成成功")
    }

    private func tearDownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// CGEvent タップのコールバック（C 関数ポインタ）
    ///
    /// `userInfo` 経由で `HotkeyService` インスタンスを取得し、`handleKeyDown` を呼ぶ。
    /// `.listenOnly` なのでイベントはそのまま通過させる。
    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        // タップが無効化された場合は再有効化する
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // userInfo から self を復元してタップを再有効化
            if let userInfo, type == .tapDisabledByTimeout {
                let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
                if let tap = service.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    print("[HotkeyService] event tap 再有効化")
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown, let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
        service.handleKeyDown(event)
        return Unmanaged.passUnretained(event)
    }

    /// キーダウンイベントを処理する
    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // 数字キー 1〜9 以外は無視
        guard let number = Self.numberKeyCodes[keyCode] else { return }

        // CGEventFlags → NSEvent.ModifierFlags に変換（比較対象のフラグだけ抽出）
        let cgFlags = event.flags
        var modFlags: NSEvent.ModifierFlags = []
        if cgFlags.contains(.maskCommand) { modFlags.insert(.command) }
        if cgFlags.contains(.maskAlternate) { modFlags.insert(.option) }
        if cgFlags.contains(.maskControl) { modFlags.insert(.control) }
        if cgFlags.contains(.maskShift) { modFlags.insert(.shift) }

        DispatchQueue.main.async { [weak self] in
            guard let self, let vm = self.viewModel else { return }

            if let appFlags = self.settings.appModifier.flags, modFlags == appFlags {
                vm.activateApp(at: number - 1)
            } else if let folderFlags = self.settings.folderModifier.flags, modFlags == folderFlags {
                vm.activateFolder(at: number - 1)
            }
        }
    }
}
