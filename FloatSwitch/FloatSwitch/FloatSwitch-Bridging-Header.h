//
//  FloatSwitch-Bridging-Header.h
//  FloatSwitch
//

// ScriptingBridge クラスへの直接キャスト (as? FinderApplication 等) は
// dyld がランタイムにシンボルを解決できずクラッシュするため使用しない。
// FinderMonitor では value(forKey:) による KVC アクセスを使用する。
