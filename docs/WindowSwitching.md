# ウィンドウ切り替え実装ノート

最終更新: 2026-03-03

---

## 概要

FloatSwitch のアイコンクリック→ウィンドウ切り替え機能の設計方針と、調査で判明した macOS API の制約をまとめる。

---

## 現在の動作仕様

| ケース                                   | 動作                                                                       |
| ---------------------------------------- | -------------------------------------------------------------------------- |
| 同 Space の複数ウィンドウ（AX が返せる） | クリックするたびに次のウィンドウへ巡回                                     |
| 別 Space のウィンドウ                    | `activate()` でそのアプリの最終使用 Space へ切り替え（ウィンドウ指定不可） |
| 最小化ウィンドウ                         | `kAXMinimizedAttribute = false` + `kAXRaiseAction` で復元                  |
| AX 権限なし                              | `activate()` のみ                                                          |

---

## 実装詳細（WindowSwitcher.swift）

### クリック時のフロー

```
activateMostRecent(app)
  │
  ├─ isContinuousTap && axWin > 1  →  ① AX 巡回（同 Space）
  │                                       cycleIndex で次のウィンドウを raise
  │
  ├─ minimized window あり         →  ② 最小化解除
  │                                       kAXMinimizedAttribute = false + kAXRaiseAction
  │
  └─ それ以外（初回 or 別アプリ）  →  ③ activate()
                                           macOS が「最終使用 Space」へ自動切り替え
```

### `isContinuousTap` の判定

`NSRunningApplication.isActive` はクリック時に一瞬 `false` になるアプリ（Chrome など）があるため使用しない。代わりに `lastActivatedPID` で「同じアイコンを連続タップ」を検出する。

```swift
private static var lastActivatedPID: pid_t = 0

let isContinuousTap = (lastActivatedPID == pid)
lastActivatedPID = pid
```

### ウィンドウ巡回インデックス

`kAXWindowsAttribute` はアプリによって `kAXRaiseAction` 後に順序を更新しないため、AX の Z 順に依存せず `static var cycleIndex: [pid_t: Int]` で自前管理する。

```swift
let next = (cycleIndex[pid] ?? 0 + 1) % ws.count
cycleIndex[pid] = next
```

---

## 調査で判明した API の制約

### 1. `kAXWindowsAttribute` は別 Space のウィンドウを返さない

Chrome などのアプリは、呼び出し元と異なる Space に存在するウィンドウを `kAXWindowsAttribute` に含めない。同一 Space のウィンドウのみ取得できる。

**ログ例（Chrome 2 ウィンドウ、別 Space）：**

```
allWindows=3  appWindows=1
  [0] size=(1800x41)   isAppWindow=false  ← Chrome 内部 UI
  [1] size=(1800x80)   isAppWindow=false  ← Chrome 内部 UI
  [2] size=(1800x1079) isAppWindow=true   ← 唯一の実ウィンドウ（もう1枚は別 Space）
```

### 2. `kAXRaiseAction` は Space をまたがない

`kAXRaiseAction` で前面に出せるのは現在の Space にあるウィンドウのみ。別 Space のウィンドウには届かない。これは `NSRunningApplication.activate()` で macOS に空間切り替えを委ねることで回避している。

### 3. `kCGWindowName` は画面収録権限が必要（macOS 10.15+）

`CGWindowListCopyWindowInfo` で取得できる `kCGWindowName`（ウィンドウタイトル）は、macOS 10.15 Catalina 以降、**画面収録権限**（Privacy - Screen Recording）がないと空文字列を返す。FloatSwitch はこの権限を持たないためウィンドウタイトルを取得できない。

> 権限なしで取得できる情報: PID、レイヤー、バウンディングボックス、`onScreen` フラグ

### 4. `CGWindowListCopyWindowInfo` のカウントは不正確

Chrome は複数の内部プロセスを持ち、それぞれが独立したウィンドウを持つ。サイズフィルタ（200×150）を掛けても Chrome の内部ウィンドウを除外しきれず、実際のブラウザウィンドウ数より多くカウントされることがある。

### 5. `app.isActive` はクリック直後に正しくない

FloatSwitch クリック後、対象アプリの `isActive` が一時的に `false` を返すことがある（特に Chrome）。Space 切り替えアニメーション中は AX が 0 ウィンドウを返す場合もある。

---

## 試みたが断念したアプローチ

| アプローチ                                          | 断念理由                                                                                     |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `kAXFocusedWindowAttribute` で巡回                  | Chrome で AX 要素の `CFEqual` 比較が失敗し、常に同一ウィンドウに戻る                         |
| `Cmd+\`` キーイベント送信                           | 別 Space のウィンドウには届かずビープ音が鳴る                                                |
| `Ctrl+↓`（App Exposé）送信                          | ユーザー設定で無効化されている場合があり、ビープ音が鳴る                                     |
| CGWindowList カウント差分で「別のウィンドウ N」表示 | カウントが過剰（内部プロセスウィンドウを含む）でかつクリックしても正しいウィンドウに届かない |
| `kCGWindowName` でタイトル取得                      | 画面収録権限なしでは空文字列                                                                 |

---

## 別 Space ウィンドウへの切り替え手段（ユーザー対応）

公開 API での実現が困難なため、以下のネイティブ操作が現実的：

- **`Cmd+\``** — 同アプリのウィンドウを次々に巡回（同 Space 内）
- **Cmd+Tab → `↓`** — アプリ切り替え後、ウィンドウ一覧を表示
- **Dock を右クリック** → 「すべてのウィンドウ」
- **Mission Control（`^↑`）** — 全 Space のウィンドウを概覧

---

## 将来の改善候補

### 画面収録権限を追加する

`NSCameraUsageDescription` のように `NSScreenCaptureUsageDescription` を Info.plist に追記し、権限をリクエストすると `kCGWindowName` が取得できるようになる。ウィンドウタイトルで右クリックメニューを充実させられる。

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>ウィンドウタイトルを取得してウィンドウ選択メニューに表示するために使用します。</string>
```

### 私的 API（リスクあり）

`CGSCopyWindowsWithOptionsAndTags` などを使えば別 Space のウィンドウ ID を取得できるが、Apple の審査は通らず、将来の macOS アップデートで破壊される可能性がある。

```swift
// 例: CGSCopySpacesForWindows（非公開）
// 参考: https://github.com/nicholasess/WindowManagement
```
