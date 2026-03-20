# FloatSwitch アーキテクチャ決定記録

最終更新: 2026-03-06

---

## 1. 配布・サンドボックス方針

| 項目 | 決定内容 |
|------|---------|
| 配布形態 | 直接配布（Developer ID 署名）|
| App Sandbox | **オフ**（`ENABLE_APP_SANDBOX = NO`） |
| 理由 | Accessibility API を使ったウィンドウ操作は App Sandbox と根本的に相性が悪く、Alfred / Raycast / Witch 等の同種アプリも全て直接配布を採用している |

---

## 2. 技術スタック

| 項目 | 採用技術 |
|------|---------|
| 言語 | Swift |
| UI フレームワーク | SwiftUI + AppKit |
| ウィンドウ管理 | `NSPanel`（`level = .floating`） |
| 状態管理 | `@Observable`（macOS 14+） |
| 最低対応 macOS | 未定（ビルド設定は現状 macOS 26.2） |

---

## 3. アプリ・ウィンドウ検出 API

### 3.1 起動中アプリ一覧

```swift
// 通常の GUI アプリのみ取得（バックグラウンドプロセス除外）
NSWorkspace.shared.runningApplications
    .filter { $0.activationPolicy == .regular }
```

**`NSRunningApplication` の主要プロパティ：**

| プロパティ | 型 | 内容 |
|-----------|-----|------|
| `localizedName` | `String?` | 表示名 |
| `bundleIdentifier` | `String?` | Bundle ID |
| `processIdentifier` | `pid_t` | PID |
| `icon` | `NSImage?` | アプリアイコン |
| `activationPolicy` | `NSApplication.ActivationPolicy` | `.regular` / `.accessory` / `.prohibited` |
| `isHidden` | `Bool` | アプリ全体の非表示状態（Cmd+H） |

> ⚠️ `isHidden` はアプリ単位の非表示（Cmd+H）のみ。ウィンドウ単位の最小化（Cmd+M）は取得できない。

---

### 3.2 リアルタイム更新

**NSWorkspace 通知（`NotificationCenter.default` ではなく専用のものを使う）：**

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification,
    object: nil,
    queue: .main
) { notification in
    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
}
```

| 通知名 | タイミング |
|--------|-----------|
| `didLaunchApplicationNotification` | アプリ起動完了 |
| `didTerminateApplicationNotification` | アプリ終了 |
| `didHideApplicationNotification` | Cmd+H で非表示 |
| `didUnhideApplicationNotification` | 非表示から復帰 |
| `didActivateApplicationNotification` | アプリがアクティブに |

**状態管理パターン：**

```
起動時: NSWorkspace.runningApplications でスナップショット取得
以降:   didLaunch → append / didTerminate → remove by PID
```

---

### 3.3 ウィンドウ最小化状態の検出

`NSRunningApplication` では取得不可。**Accessibility API** が必要。

```swift
// 必要な権限: アクセシビリティ（システム設定 > プライバシー > アクセシビリティ）
let appElement = AXUIElementCreateApplication(app.processIdentifier)

var windowsRef: CFTypeRef?
AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

if let windows = windowsRef as? [AXUIElement] {
    for window in windows {
        var minimizedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
        let isMinimized = (minimizedRef as? Bool) ?? false
    }
}
```

**主要 Accessibility API：**

| API / 定数 | 役割 |
|-----------|------|
| `AXUIElementCreateApplication(pid)` | PID からアプリ要素を作成 |
| `AXUIElementCopyAttributeValue(_:_:_:)` | 属性値を取得 |
| `kAXWindowsAttribute` | ウィンドウ一覧 |
| `kAXMinimizedAttribute` | 最小化状態 |
| `kAXTitleAttribute` | ウィンドウタイトル |
| `kAXRaiseAction` | ウィンドウを前面に出す |
| `AXIsProcessTrusted()` | アクセシビリティ権限の確認 |

---

### 3.4 Finder ウィンドウ（フォルダ）の取得

**採用：ScriptingBridge**（Accessibility API より確実にフルパスを取得できるため）

比較検討の結果：

| 観点 | Accessibility API | ScriptingBridge（採用） |
|------|------------------|----------------------|
| フルパス取得 | 不安定（`kAXURLAttribute` に依存） | 安定（`target` プロパティ） |
| 最小化状態 | 可能 | 可能（`miniaturized`） |
| 実装複雑さ | 高い | 中程度 |
| 将来性 | ◎ | ◎（ScriptingBridge 自体は安定） |

**⚠️ 型キャスト禁止（dyld クラッシュ）**

ScriptingBridge が動的生成するクラス（`FinderApplication`, `FinderFinderWindow` 等）への
Swift 型キャスト（`as? FinderApplication`）はバイナリに静的シンボル参照を埋め込むため、
dyld がランタイムロード時に `symbol not found` でクラッシュする。

**採用：KVC アクセス（`value(forKey:)`）**

```swift
// NG: as? FinderApplication → dyld クラッシュ
// OK: value(forKey:) で動的アクセス
guard let finder = SBApplication(bundleIdentifier: "com.apple.finder"),
      let windows = finder.value(forKey: "FinderWindows") as? [AnyObject] else { return }

for window in windows {
    guard let nsWindow = window as? NSObject,
          let target = nsWindow.value(forKey: "target") as? NSObject,
          let urlString = target.value(forKey: "URL") as? String,  // KVC は ObjC 名 "URL" をそのまま使う
          let url = URL(string: urlString) else { continue }
    // url がフォルダのフルパス
}
```

**更新方式：ポーリング（1〜2秒間隔）**
- Finder のウィンドウ開閉・フォルダ移動は NSWorkspace 通知でカバー不可
- `Timer` で定期取得し、前回との差分を比較して更新

---

## 4. 設定の永続化

| 設定 | 保存先 | 方式 |
|------|--------|------|
| ホットキー（修飾キー） | UserDefaults `hotkeySettings_v1` | JSON (Codable) |
| 外観（向き・サイズ・グラデーション等） | UserDefaults `appAppearance_v1` | JSON (Codable) |
| 非表示アプリ・表示順序 | `~/.config/floatswitch/hidden_apps.json` | JSON ファイル |

---

## 5. ディレクトリ構成

```
FloatSwitch/FloatSwitch/
├── FloatSwitchApp.swift       # @main、AppDelegate 接続
├── AppDelegate.swift           # NSPanel 生成・Monitor 初期化・設定画面
├── FloatingPanel.swift         # NSPanel サブクラス
├── Models/
│   └── AppItem.swift           # アプリ・フォルダのデータモデル
├── Services/
│   ├── AppMonitor.swift        # NSWorkspace 通知でアプリ監視
│   ├── AppViewModel.swift      # 状態管理（@Observable）・外観設定永続化
│   ├── AppCustomization.swift  # 非表示・並び順の管理
│   ├── HotkeySettings.swift    # ホットキー設定の永続化
│   └── HotkeyService.swift     # グローバルホットキー監視
├── Views/
│   ├── FloatingBarView.swift   # フローティングバーのルートビュー
│   ├── FloatingBarShape.swift  # 湾曲シェイプ
│   ├── MagnifyingIconRow.swift # Dock 風拡大エフェクト付きアイコン列
│   └── SettingsView.swift      # 設定画面（ホットキー・外観）
└── Utilities/
```

---

## 5. 必要な権限

| 権限 | 用途 | 取得タイミング |
|------|------|-------------|
| アクセシビリティ | ウィンドウ最小化状態の取得・ウィンドウ操作 | 初回起動時にプロンプト表示 |
| Apple Events 自動化 | ScriptingBridge で Finder 操作 | 初回起動時にプロンプト表示 |

Info.plist への追記が必要：
```xml
<key>NSAppleEventsUsageDescription</key>
<string>Finder で開いているフォルダの一覧を取得するために使用します。</string>
```
