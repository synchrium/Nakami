//
//  ShortcutsView.swift
//  Nakami
//
//  Created by synchrium on 2026/10/31
//
//  Copyright (C) 2026  synchrium
//

import SwiftUI

/// 早見表の 1 行
struct Shortcut: Identifiable {
    let id = UUID()
    let keys: [String]      // 押すキー（例: ["⌘", "⇧", "G"]）。"→" は「続けて押す」
    let action: String      // すること
    let windows: String     // Windows では

    /// 文字は LocalizedStringResource で受け取り、その場で今の言語の文字にする
    /// （Xcode がビルドのときに String Catalog へ集めてくれる）
    init(_ keys: [String], _ action: LocalizedStringResource, windows: LocalizedStringResource? = nil) {
        self.keys = keys
        self.action = String(localized: action)
        self.windows = windows.map { String(localized: $0) } ?? ""
    }
}

struct ShortcutSection: Identifiable {
    let id = UUID()
    let title: String
    let note: String?
    let items: [Shortcut]

    init(title: LocalizedStringResource, note: LocalizedStringResource?, items: [Shortcut]) {
        self.title = String(localized: title)
        self.note = note.map { String(localized: $0) }
        self.items = items
    }

    /// 検索で絞ったときに、見出しはそのままで中身だけ入れ替えたものを作る
    init(copying section: ShortcutSection, items: [Shortcut]) {
        self.title = section.title
        self.note = section.note
        self.items = items
    }
}

/// キーの名前で訳が要るもの
private let click = String(localized: "クリック")
private let drag = String(localized: "ドラッグ")

/// 早見表の中身。Nakami と、書庫を扱うときに使う Finder やダイアログのキーに絞る
/// （全部の一覧は Notion の「Mac のショートカットキー一覧」）
let shortcutSections: [ShortcutSection] = [
    ShortcutSection(title: "記号の読み方", note: "Mac のキーボードの記号と、Windows でだいたい当たるキー", items: [
        Shortcut(["⌘"], "command", windows: "だいたい Ctrl"),
        Shortcut(["⇧"], "shift", windows: "Shift"),
        Shortcut(["⌥"], "option", windows: "だいたい Alt"),
        Shortcut(["⌃"], "control", windows: "Mac ではあまり使わない"),
        Shortcut(["⌫"], "delete（左を消す）", windows: "Backspace"),
    ]),
    ShortcutSection(title: "Nakami", note: nil, items: [
        Shortcut(["⌘", "O"], "書庫を開く", windows: "Ctrl+O"),
        Shortcut(["⌘", "N"], "新しい書庫を作る", windows: "7-Zip の「追加」"),
        Shortcut(["⌘", "E"], "取り出す（何も選ばなければ全部）", windows: "7-Zip の「展開」"),
        Shortcut([drag], "Finder へ取り出す（そのまま置く）", windows: "7-Zip から Explorer へドラッグ"),
        Shortcut(["Return"], "フォルダに入る・ファイルを開く（ダブルクリックでも）", windows: "Enter"),
        Shortcut(["⌘", "↑"], "上のフォルダへ", windows: "Backspace（7-Zip）"),
        Shortcut(["⌫"], "上のフォルダへ（Windows の癖で押しても効く）", windows: "Backspace（7-Zip）"),
        Shortcut(["Space"], "選んだファイルを Quick Look で見る", windows: "プレビュー ウィンドウ（Alt+P）"),
        Shortcut(["⌘", click], "1 つずつ足して選ぶ", windows: "Ctrl+クリック"),
        Shortcut(["⇧", click], "範囲で選ぶ", windows: "Shift+クリック"),
        Shortcut(["⌥", "⌘", "A"], "選択を解除（⌘E が全部を取り出すようになる）", windows: "—"),
        Shortcut(["⌘", "W"], "窓を閉じる（アプリは終わらない）", windows: "Ctrl+W"),
        Shortcut(["Esc"], "窓を閉じる（設定でオンにしたとき）", windows: "Esc"),
        Shortcut(["⌘", "Q"], "アプリを終わる", windows: "Alt+F4"),
        Shortcut(["⌘", "?"], "この早見表", windows: "F1"),
    ]),
    ShortcutSection(title: "新しい書庫の窓（⌘N）", note: "Finder からファイルやフォルダをドロップして組み立てる", items: [
        Shortcut(["⇧", "⌘", "N"], "新しいフォルダを作る", windows: "Ctrl+Shift+N"),
        Shortcut(["⌘", "⌫"], "選んだものを外す（元のファイルは消えない）", windows: "Delete"),
        Shortcut(["⌘", "S"], "書庫を作る", windows: "7-Zip の「OK」"),
        Shortcut(["⌥", "⌘", "N"], "書庫を見る窓を開く", windows: "—"),
    ]),
    ShortcutSection(title: "Finder", note: "書庫を探したり、取り出したファイルを見たりするとき", items: [
        Shortcut(["Space"], "Quick Look（開かずに中を見る）", windows: "プレビュー ウィンドウ（Alt+P）"),
        Shortcut(["⌘", "↓"], "開く", windows: "Enter"),
        Shortcut(["Return"], "名前を変える（開くのではない！）", windows: "F2"),
        Shortcut(["⌘", "↑"], "上のフォルダへ", windows: "Alt+↑"),
        Shortcut(["⌘", "⇧", "G"], "フォルダへ移動（パスを打つ。Tab で補完）", windows: "Ctrl+L"),
        Shortcut(["⌘", "⇧", "."], "隠しファイルを出す・隠す", windows: "「隠しファイル」のチェック"),
        Shortcut(["⌘", "I"], "情報を見る（既定のアプリもここで変える）", windows: "Alt+Enter"),
        Shortcut(["⌥", "⌘", "C"], "パスをコピー", windows: "Shift+右クリック →「パスのコピー」"),
        Shortcut(["⌘", "C", "→", "⌥", "⌘", "V"], "移動（Finder に ⌘X は無い）", windows: "Ctrl+X → Ctrl+V"),
        Shortcut(["⌘", "⌫"], "ゴミ箱へ", windows: "Delete"),
    ]),
    ShortcutSection(title: "「開く」「保存」のダイアログ", note: nil, items: [
        Shortcut(["⌘", "⇧", "G"], "フォルダへ移動", windows: "ファイル名の欄にパスを打つ"),
        Shortcut(["⌘", "⇧", "."], "隠しファイルを出す"),
        Shortcut(["⌘", "⇧", "H"], "ホームへ"),
        Shortcut(["⌘", "⇧", "D"], "デスクトップへ"),
    ]),
    ShortcutSection(title: "全般", note: nil, items: [
        Shortcut(["⌘", "Space"], "Spotlight（アプリやファイルを名前で開く）", windows: "Win キーで検索"),
        Shortcut(["⌘", "Tab"], "アプリの切り替え", windows: "Alt+Tab"),
        Shortcut(["⌘", "`"], "同じアプリの窓の切り替え"),
        Shortcut(["⌥", "⌘", "Esc"], "アプリの強制終了", windows: "Ctrl+Shift+Esc"),
        Shortcut(["⌘", "⇧", "4"], "範囲を選んでスクリーンショット", windows: "Win+Shift+S"),
    ]),
]

/// キーボードのキーの形で 1 つのキーを描く
private struct KeyCap: View {
    let key: String

    var body: some View {
        if key == "→" {
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(key)
                .font(.system(.body, design: .rounded).weight(.medium))
                .frame(minWidth: 22)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.tertiary))
        }
    }
}

struct ShortcutsView: View {
    @State private var query = ""

    // 区切りごとに別の表なので、列の幅を決めておかないと列の位置がずれる
    private let keyColumnWidth: CGFloat = 170
    private let actionColumnWidth: CGFloat = 300

    /// 検索欄に入れた言葉で絞る（すること・Windows の列・キーのどれかに含まれていれば出す）
    private var filtered: [ShortcutSection] {
        guard !query.isEmpty else { return shortcutSections }
        return shortcutSections.compactMap { section in
            let items = section.items.filter {
                $0.action.localizedCaseInsensitiveContains(query)
                    || $0.windows.localizedCaseInsensitiveContains(query)
                    || $0.keys.joined().localizedCaseInsensitiveContains(query)
            }
            return items.isEmpty ? nil : ShortcutSection(copying: section, items: items)
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { section in
                Section {
                    // Grid は表の形に並べる（WPF の Grid に近い）。列の幅は中身に合わせてそろう
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("キー").frame(width: keyColumnWidth, alignment: .leading)
                            Text("すること").frame(width: actionColumnWidth, alignment: .leading)
                            Text("Windows では")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ForEach(section.items) { item in
                            GridRow {
                                HStack(spacing: 3) {
                                    ForEach(Array(item.keys.enumerated()), id: \.offset) { _, key in
                                        KeyCap(key: key)
                                    }
                                }
                                .frame(width: keyColumnWidth, alignment: .leading)
                                Text(item.action)
                                    .frame(width: actionColumnWidth, alignment: .leading)
                                Text(item.windows)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title).font(.headline)
                        if let note = section.note {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "探す（例: 隠し、Alt）")
        .frame(minWidth: 720, minHeight: 480)
    }
}

#Preview {
    ShortcutsView()
}
