//
//  SettingsView.swift
//  Nakami
//
//  Created by synchrium on 2026/10/31
//
//  Copyright (C) 2026  synchrium
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// ⌘E で 1 つだけ選んで取り出すときの置き方
enum SingleItemPlacement: String, CaseIterable, Identifiable {
    case wrap = "書庫の名前のフォルダに入れる"
    case direct = "そのまま置く"

    var id: Self { self }

    /// 画面に出す名前（rawValue は設定の保存に使うので、表示はこちら）
    var label: LocalizedStringResource {
        switch self {
        case .wrap: "書庫の名前のフォルダに入れる"
        case .direct: "そのまま置く"
        }
    }
}

/// 設定の名前（UserDefaults のキー）。ここにまとめておき、打ち間違いを防ぐ
enum SettingsKey {
    static let singleItemPlacement = "singleItemPlacement"
    static let revealAfterExtract = "revealAfterExtract"
    static let defaultEncoding = "defaultEncoding"
    static let quitWhenLastWindowClosed = "quitWhenLastWindowClosed"
    static let escClosesWindow = "escClosesWindow"
    static let composeFormat = "composeFormat"
    static let composeEncoding = "composeEncoding"
    static let composeEncryption = "composeEncryption"
    static let revealAfterCompose = "revealAfterCompose"
}

/// 設定の窓（⌘,）。Finder や Safari の設定と同じく、上のタブで切り替える
/// （Windows のプロパティシートのタブに当たる）。
/// Settings の中に TabView を置くと、macOS が窓の上にアイコン付きのタブを並べてくれる
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("一般", systemImage: "gearshape") { GeneralSettings() }
            Tab("取り出す", systemImage: "square.and.arrow.down") { ExtractSettings() }
            Tab("作る", systemImage: "archivebox") { ComposeSettings() }
            Tab("既定のアプリ", systemImage: "doc.zipper") { DefaultAppSettings() }
        }
        .frame(width: 560)
    }
}

/// 一般：アプリの動きとファイル名。
/// @AppStorage は UserDefaults に保存する（Windows のレジストリ HKCU\Software\… や .NET の Properties.Settings.Default に当たる）
struct GeneralSettings: View {
    @AppStorage(SettingsKey.quitWhenLastWindowClosed) private var quitWhenLastWindowClosed = false
    @AppStorage(SettingsKey.escClosesWindow) private var escClosesWindow = false
    @AppStorage(SettingsKey.defaultEncoding) private var defaultEncoding: NameEncoding = .auto

    var body: some View {
        Form {
            Section("アプリ") {
                Toggle("最後の窓を閉じたら Nakami を終わる", isOn: $quitWhenLastWindowClosed)
                Text("オフのときは Mac のふつうの動き（窓を閉じてもアプリは動いたまま。Dock のアイコンですぐ開ける）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Esc で窓を閉じる", isOn: $escClosesWindow)
                Text("Quick Look のように、Esc で窓を閉じます。上の設定と合わせると、Esc で Nakami を終われます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("ファイル名") {
                Picker("文字コードの既定", selection: $defaultEncoding) {
                    ForEach(NameEncoding.allCases) { Text($0.label).tag($0) }
                }
                Text("書庫を開いたときの文字コード。開いたあとはツールバーで切り替えられます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 取り出す（⌘E）
struct ExtractSettings: View {
    @AppStorage(SettingsKey.singleItemPlacement) private var placement: SingleItemPlacement = .wrap
    @AppStorage(SettingsKey.revealAfterExtract) private var revealAfterExtract = true

    var body: some View {
        Form {
            Section("取り出す（⌘E）") {
                Picker("1 つだけ選んだとき", selection: $placement) {
                    ForEach(SingleItemPlacement.allCases) { Text($0.label).tag($0) }
                }
                (placement == .wrap
                     ? Text("例：「表.csv」を選んで取り出すと「取り出し先/sjis/表.csv」")
                     : Text("例：「表.csv」を選んで取り出すと「取り出し先/表.csv」"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("何個か選んだときと全部のときは、いつも書庫の名前のフォルダに入れます（中身が 1 つのフォルダにまとまっていればそのまま）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("取り出したあと Finder で見せる", isOn: $revealAfterExtract)
            }
            Section {
                Text("Finder へのドラッグで取り出すときは、この設定に関係なく、ドロップした場所にそのまま置きます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 作る（⌘N の新しい書庫）。ここで決めるのは窓を開いたときの値で、窓のツールバーでも切り替えられる
struct ComposeSettings: View {
    @AppStorage(SettingsKey.composeFormat) private var format: ArchiveFormat = .zip
    @AppStorage(SettingsKey.composeEncoding) private var encoding: WriteEncoding = .utf8
    @AppStorage(SettingsKey.composeEncryption) private var encryption: ZipEncryption = .aes256
    @AppStorage(SettingsKey.revealAfterCompose) private var revealAfterCompose = true

    var body: some View {
        Form {
            Section("新しい書庫（⌘N）") {
                Picker("形式の既定", selection: $format) {
                    ForEach(ArchiveFormat.allCases) { Text(verbatim: $0.fileExtension).tag($0) }
                }
                Toggle("作ったあと Finder で見せる", isOn: $revealAfterCompose)
            }
            Section("zip のとき") {
                Picker("文字コードの既定", selection: $encoding) {
                    ForEach(WriteEncoding.allCases) { Text($0.label).tag($0) }
                }
                Text("Mac と Windows 10 以降は UTF-8 で読めます。古い Windows や古いソフトに渡すなら Shift_JIS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("パスワードの方式", selection: $encryption) {
                    ForEach(ZipEncryption.allCases) { Text($0.label).tag($0) }
                }
                Text("AES-256 の zip は、相手が 7-Zip などを使えば開けます。Windows のエクスプローラーだけで開いてもらうなら ZipCrypto")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Mac のゴミ（`.DS_Store`・`__MACOSX`・`._` で始まるもの）は、いつも入れません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 既定のアプリ：Finder でダブルクリックしたときに Nakami で開くか。種類ごとに選ぶ
struct DefaultAppSettings: View {
    /// Nakami で開ける種類（Nakami-Info.plist の CFBundleDocumentTypes から読む）
    private let types: [UTType] = {
        let docTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        return docTypes
            .flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
            .compactMap { UTType($0) }
    }()

    /// 種類ごとの、今開くアプリの名前（キーは UTI）
    @State private var handlers: [String: String] = [:]
    /// 種類ごとの、今開くアプリが Nakami か
    @State private var isNakami: [String: Bool] = [:]
    @State private var changing = false

    var body: some View {
        Form {
            Section {
                ForEach(types, id: \.identifier) { type in
                    // 1 行に「拡張子・種類の名前・今のアプリ・スイッチ」を並べる
                    Toggle(isOn: Binding(
                        get: { isNakami[type.identifier] ?? false },
                        set: { on in Task { await change([type], toNakami: on) } }
                    )) {
                        HStack {
                            Text(verbatim: "." + (type.preferredFilenameExtension ?? ""))
                                .monospaced()
                                .frame(width: 56, alignment: .leading)
                            // macOS が持っている種類の名前（「ZIP アーカイブ」など。言語に合わせて出る）
                            Text(verbatim: type.localizedDescription ?? "")
                            Spacer()
                            Text(verbatim: handlers[type.identifier] ?? "—")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(changing)
                }
            } header: {
                HStack {
                    Text("Nakami で開く種類")
                    Spacer()
                    Button("すべてオン") { Task { await change(types, toNakami: true) } }
                    Button("すべてオフ") { Task { await change(types, toNakami: false) } }
                }
                .disabled(changing)
            } footer: {
                Text("オンにした種類は、Finder でダブルクリックすると Nakami で開きます。オフにするとアーカイブユーティリティ（なければほかの対応アプリ）に戻します。変えるたびに macOS が確認します。Nakami は「アプリケーション」フォルダに置いてから設定してください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
        .onAppear(perform: refresh)
    }

    /// 種類ごとに、今開くアプリを調べ直す（Windows の「既定のアプリ」の一覧）
    private func refresh() {
        for type in types {
            let app = NSWorkspace.shared.urlForApplication(toOpen: type)
            handlers[type.identifier] = app.map { FileManager.default.displayName(atPath: $0.path) } ?? "—"
            isNakami[type.identifier] = app.flatMap { Bundle(url: $0)?.bundleIdentifier } == Bundle.main.bundleIdentifier
        }
    }

    /// macOS（LaunchServices）に既定のアプリを頼む。Windows の UserChoice をユーザーの確認つきで変えるのに近い
    private func change(_ types: [UTType], toNakami on: Bool) async {
        changing = true
        defer { changing = false }
        for type in types where (isNakami[type.identifier] ?? false) != on {
            await change(type, toNakami: on)
        }
        refresh()
    }

    private func change(_ type: UTType, toNakami on: Bool) async {
        let target: URL?
        if on {
            target = Bundle.main.bundleURL
        } else {
            // Nakami 以外で、その種類を開けるアプリ。アーカイブユーティリティがあればそれ
            let utility = URL(filePath: "/System/Library/CoreServices/Applications/Archive Utility.app")
            let others = NSWorkspace.shared.urlsForApplications(toOpen: type)
                .filter { Bundle(url: $0)?.bundleIdentifier != Bundle.main.bundleIdentifier }
            target = others.first { $0.standardizedFileURL == utility.standardizedFileURL } ?? others.first
        }
        if let target {
            // 確認でキャンセルされたら何も変わらない（下の refresh で元の表示に戻る）
            try? await NSWorkspace.shared.setDefaultApplication(at: target, toOpen: type)
        }
        refresh()
    }
}

#Preview {
    SettingsView()
}
