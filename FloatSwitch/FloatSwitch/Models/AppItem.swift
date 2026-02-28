//
//  AppItem.swift
//  FloatSwitch
//

import AppKit

/// アプリ・フォルダのデータモデル
struct AppItem: Identifiable {
    enum Kind {
        case app(NSRunningApplication)
        case folder(URL)
    }

    let id: String
    let kind: Kind
    let name: String
    let icon: NSImage?

    init(app: NSRunningApplication) {
        id = "app-\(app.processIdentifier)"
        kind = .app(app)
        name = app.localizedName ?? "Unknown"
        icon = app.icon
    }

    init(folderURL: URL) {
        id = "folder-\(folderURL.path)"
        kind = .folder(folderURL)
        name = folderURL.lastPathComponent
        icon = NSWorkspace.shared.icon(forFile: folderURL.path)
    }
}
