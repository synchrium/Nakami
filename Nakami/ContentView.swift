//
//  ContentView.swift
//  Nakami
//
//  Created by synchrium on 2026/10/31
//
//  Copyright (C) 2026  synchrium
//

import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// 画面に出すお知らせ（エラーや取り出しの結果）
struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ContentView: View {
    @State private var archiveURL: URL?
    @State private var entries: [ArchiveEntry] = []
    @State private var currentDir = ""                 // 今いるフォルダ（"" がいちばん上、"資料/" のように「/」で終わる）
    @State private var items: [ListItem] = []          // 今いるフォルダの中身（一覧に出すもの）
    @State private var selection = Set<ListItem.ID>()
    @State private var notice: Notice?
    @State private var showingImporter = false
    @State private var encoding: NameEncoding = .auto
    @State private var extracting = false

    // パスワード付きの zip。入れたパスワードは窓を閉じるまで覚えておく（保存はしない）
    @State private var isZip = false
    @State private var password: String?
    @State private var showingPassword = false
    @State private var afterPassword: (() -> Void)?     // パスワードが合ったら続きにやること

    // スペースキーの Quick Look。見せているファイルと、← → で切り替えられるファイルの一覧
    @State private var quickLookURL: URL?
    @State private var quickLookURLs: [URL] = []

    // 設定（⌘,）の値。設定の窓で変えると、ここにもすぐ反映される
    @AppStorage(SettingsKey.singleItemPlacement) private var placement: SingleItemPlacement = .wrap
    @AppStorage(SettingsKey.revealAfterExtract) private var revealAfterExtract = true
    @AppStorage(SettingsKey.defaultEncoding) private var defaultEncoding: NameEncoding = .auto

    /// キーボードの操作の対象（フォーカス）が一覧にあるか
    @FocusState private var tableFocused: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if archiveURL == nil {
                ContentUnavailableView {
                    Label("書庫を開いてください", systemImage: "doc.zipper")
                } description: {
                    Text("ここに zip をドロップするか、ツールバーの「開く」（⌘O）で選びます")
                } actions: {
                    Button("新しい書庫を作る（⌘N）") { openWindow(id: "compose") }
                }
            } else {
                VStack(spacing: 0) {
                    pathBar
                    Divider()
                    table
                    Divider()
                    statusBar
                }
            }
        }
        .frame(minWidth: 600, minHeight: 360)
        .navigationTitle(archiveURL?.lastPathComponent ?? "Nakami")
        .toolbar { toolbarContent }
        .overlay {
            if extracting {
                ProgressView("取り出しています…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        // 「開く」ダイアログ（Win32 の GetOpenFileName / IFileOpenDialog に当たる）
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.archive]) { result in
            switch result {
            case .success(let url): open(url)
            case .failure(let error): notice = Notice(title: String(localized: "開けませんでした"), message: error.localizedDescription)
            }
        }
        // ドラッグ＆ドロップ（WM_DROPFILES / IDropTarget に当たる）
        .dropDestination(for: URL.self) { urls, _ in
            // 自分の一覧からドラッグしたものを自分の窓に落としたときは、何もしない
            guard let url = urls.first, !url.path.hasPrefix(DragItem.root.path) else { return false }
            // 書庫を開いていて、落とされたのが書庫 1 つでなければ、書庫に足す（7-Zip と同じ）。
            // 編集の窓を開いて足した状態にするだけで、保存するまで書庫は変わらない
            if archiveURL != nil, !(urls.count == 1 && isArchive(url)) {
                edit(adding: urls)
                return true
            }
            open(url)
            return true
        }
        // Finder でダブルクリックされた書庫（「このアプリケーションで開く」も）。
        // Windows ではコマンドライン引数（%1）で来るが、Mac では「開け」というメッセージで来る
        .onOpenURL { url in open(url) }
        // 編集の窓で上書き保存された。同じ書庫を開いていれば読み直す
        .onReceive(NotificationCenter.default.publisher(for: .archiveDidChange)) { note in
            guard let changed = note.object as? URL, let archiveURL,
                  changed.standardizedFileURL == archiveURL.standardizedFileURL else { return }
            reload()
        }
        // 文字コードを変えると名前（＝フォルダの名前）が変わるので、いちばん上に戻る
        .onChange(of: encoding) { currentDir = ""; refreshItems() }
        .onChange(of: currentDir) { refreshItems() }
        // パスワードを聞くシート
        // Quick Look の窓（Finder でスペースキーを押したときと同じもの）
        .quickLookPreview($quickLookURL, in: quickLookURLs)
        .sheet(isPresented: $showingPassword) {
            PasswordSheet(
                archiveName: archiveURL?.lastPathComponent ?? "",
                check: checkPassword,
                cancel: {
                    afterPassword = nil
                    showingPassword = false
                }
            )
        }
        .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
               presenting: notice) { _ in
            Button("OK") {}
        } message: { n in
            Text(n.message)
        }
    }

    private func open(_ url: URL) {
        // サンドボックスの中のアプリは、ユーザーが選んだファイルだけ読める。
        // 取り出すときにも読むので、窓で開いている間は「読んでよい」という許可を有効にしておく。
        // 古い許可を返すのは、新しい書庫を開けてから（同じファイルを開き直したとき、
        // 先に返すと新しい許可まで取り消されて開けなくなる。開けなかったときは前の書庫をそのまま使えるように）
        _ = url.startAccessingSecurityScopedResource()

        do {
            let listing = try ArchiveReader.list(url)
            archiveURL?.stopAccessingSecurityScopedResource()
            entries = listing.entries
            isZip = listing.isZip
            password = nil
            archiveURL = url
            encoding = defaultEncoding
            currentDir = ""
            refreshItems()
            // パスワード付きでも、開いたときには聞かない・知らせない（7-Zip と同じ）。
            // zip のパスワードが守るのは中身だけで、ファイル名やサイズはもともと誰でも見られるため。
            // 取り出す・開くときか、ステータスバーの鍵をクリックしたときに聞く。
            // 7z・rar のパスワード付きは、取り出す・開くときに「対応していない」と知らせる
        } catch {
            url.stopAccessingSecurityScopedResource()
            // 書庫でないファイル（PDF など）なら、libarchive の英語のエラーではなく案内を出す
            let message = isArchive(url) ? error.localizedDescription
                : String(localized: "「\(url.lastPathComponent)」は書庫ではありません。新しい書庫を作るときは ⌘N の窓に入れてください")
            notice = Notice(title: String(localized: "開けませんでした"), message: message)
        }
    }

    /// 開いている書庫を読み直す（編集の窓で保存されたとき）。今いるフォルダと文字コードとパスワードはそのまま
    private func reload() {
        guard let archiveURL, let listing = try? ArchiveReader.list(archiveURL) else { return }
        entries = listing.entries
        isZip = listing.isZip
        // パスワードを外して保存されたら、もう要らない
        if !entries.contains(where: \.isEncrypted) { password = nil }
        // 今いるフォルダが無くなっていたら、いちばん上へ
        if !currentDir.isEmpty, !entries.contains(where: { $0.path(encoding).hasPrefix(currentDir) }) {
            currentDir = ""
        }
        refreshItems()
    }

    // MARK: - 編集

    /// 書庫の種類のファイルか（zip・7z・tar.gz など。種類は拡張子から macOS が決めたもの）
    private func isArchive(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .archive)) ?? false
    }

    /// 今ある書庫を編集する。全部を一時フォルダに取り出し、新しい書庫の窓に読み込む。
    /// adding は、見る窓に落とされて足すもの（編集の窓で最初から足した状態にする）
    private func edit(adding: [URL] = []) {
        guard let archiveURL else { return }
        guard let format = EditSession.format(of: archiveURL) else {
            notice = Notice(title: String(localized: "編集できません"),
                            message: String(localized: "編集できるのは zip・7z・tar.gz・tar.xz です"))
            return
        }
        if blockedByUnsupportedPassword(nil) { return }
        if needsPassword(nil) {
            askPassword { edit(adding: adding) }
            return
        }

        let encoding = encoding
        let writeEncoding = zipWriteEncoding()
        let passphrase = password
        let folder = EditSession.newFolder()
        extracting = true
        Task {
            let result = await Task.detached {
                Result {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    return try ArchiveExtractor.extract(archiveURL, ids: nil, encoding: encoding,
                                                        passphrase: passphrase, to: folder)
                }
            }.value
            extracting = false

            switch result {
            case .success(let r) where r.failed.isEmpty && r.skipped.isEmpty:
                let session = EditSession(archiveURL: archiveURL, folder: folder, format: format,
                                          encoding: writeEncoding, password: format.isZip ? passphrase : nil)
                EditSession.register(session)
                openWindow(id: "compose", value: ComposeRequest(urls: adding, editID: session.id))
            case .success(let r):
                // 全部を取り出せなければ、保存したときに中身が消えてしまうので編集させない
                try? FileManager.default.removeItem(at: folder)
                notice = Notice(title: String(localized: "編集できません"),
                                message: String(localized: "書庫の中身を全部は取り出せませんでした。") + "\n\n" + summary(r))
            case .failure(let error):
                try? FileManager.default.removeItem(at: folder)
                notice = Notice(title: String(localized: "編集できません"), message: error.localizedDescription)
            }
        }
    }

    /// 編集した zip を保存するときの名前の文字コード。今の表示で Shift_JIS として読んでいる名前があれば Shift_JIS
    /// （Windows で作った zip を編集して、Windows の人に返すときに化けないように）
    private func zipWriteEncoding() -> WriteEncoding {
        switch encoding {
        case .shiftJIS: return .shiftJIS
        case .utf8: return .utf8
        case .auto:
            let sjis = entries.contains { $0.utf8Name == nil && String(validating: $0.rawName, as: UTF8.self) == nil }
            return sjis ? .shiftJIS : .utf8
        }
    }

    // MARK: - ツールバー

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 左（タイトルの横）：上のフォルダへ
        ToolbarItem(placement: .navigation) {
            Button("上へ", systemImage: "chevron.left") { goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("上のフォルダへ（⌘↑）")
                .disabled(currentDir.isEmpty)
        }
        // 右：文字コード・取り出す・開く
        ToolbarItemGroup(placement: .primaryAction) {
            // ファイル名の文字コード。書庫は読み直さず、表示だけ変わる
            Picker("文字コード", selection: $encoding) {
                ForEach(NameEncoding.allCases) { Text($0.label).tag($0) }
            }
            .help("ファイル名の文字コード")
            // 選んでいると ⌘E は「選んだものだけ」になるので、すぐ外せるようにする（Finder と同じ ⌥⌘A）
            Button("選択を解除", systemImage: "xmark.circle") { selection = [] }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .help("選択を解除して、⌘E で全部を取り出せるようにする（⌥⌘A）")
                .disabled(selection.isEmpty)
            Button("取り出す", systemImage: "square.and.arrow.down") { chooseDestinationAndExtract(selection) }
                .keyboardShortcut("e")
                .help(selection.isEmpty ? Text("全部を取り出す（⌘E）") : Text("選んだものを取り出す（⌘E）"))
                .disabled(archiveURL == nil || extracting)
            Button("編集", systemImage: "pencil") { edit() }
                .help(archiveURL.flatMap(EditSession.format(of:)) == nil
                      ? Text("編集できるのは zip・7z・tar.gz・tar.xz です")
                      : Text("ファイルを足す・外す・名前を変える（新しい書庫の窓で開きます）"))
                .disabled(archiveURL.flatMap(EditSession.format(of:)) == nil || extracting)
            Button("開く", systemImage: "folder") { showingImporter = true }
                .keyboardShortcut("o")
                .help("書庫を開く（⌘O）")
        }
    }

    // MARK: - 一覧とフォルダの移動

    /// 今いるフォルダの場所（パンくず）。クリックでその階層へ跳ぶ
    private var pathBar: some View {
        let parts = currentDir.split(separator: "/").map(String.init)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button { currentDir = "" } label: {
                    Label(archiveURL?.lastPathComponent ?? "", systemImage: "doc.zipper")
                }
                ForEach(parts.indices, id: \.self) { i in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button(parts[i]) { currentDir = parts[...i].map { $0 + "/" }.joined() }
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    /// 窓の下の帯（Finder のステータスバーと同じ）。左に項目数とサイズ、右にパスワードの状態
    private var statusBar: some View {
        let selected = items.filter { selection.contains($0.id) }
        let hasEncrypted = entries.contains(where: \.isEncrypted)
        return HStack {
            if selected.isEmpty {
                Text("\(items.count) 項目・\(totalSize(items))")
            } else {
                Text("\(selected.count) / \(items.count) 項目を選択・\(totalSize(selected))")
            }
            Spacer()
            if hasEncrypted && !isZip {
                Label("パスワード非対応の形式", systemImage: "lock.slash")
            } else if hasEncrypted && password != nil {
                Label("パスワード OK", systemImage: "lock.open.fill")
            } else if hasEncrypted {
                // まだ入れていなければ、クリックでパスワードを聞く
                Button { askPassword(then: nil) } label: {
                    Label("パスワード未入力（クリックで入力）", systemImage: "lock.fill")
                }
                .buttonStyle(.borderless)
                .focusable(false)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func totalSize(_ items: [ListItem]) -> String {
        items.reduce(Int64(0)) { $0 + $1.size }.formatted(.byteCount(style: .file))
    }

    private var table: some View {
        // selection を渡すと、クリック・⌘クリック・⇧クリックで選べるようになる（WPF の SelectionMode="Extended"）
        Table(of: ListItem.self, selection: $selection) {
            TableColumn("名前") { item in
                HStack(spacing: 4) {
                    Label(item.name, systemImage: item.isDirectory ? "folder" : "doc")
                    if item.containsEncrypted {
                        // パスワードが通っていれば開いた鍵
                        Image(systemName: password == nil ? "lock.fill" : "lock.open.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("パスワード付き")
                    }
                }
            }
            TableColumn("サイズ") { item in
                Text(item.size.formatted(.byteCount(style: .file)))
                    .monospacedDigit()
                    .foregroundStyle(item.isDirectory ? .secondary : .primary)
            }
            .width(min: 60, ideal: 90)
            TableColumn("更新日時") { item in
                Text(item.modified?.formatted(date: .numeric, time: .shortened) ?? "")
            }
            .width(min: 100, ideal: 140)
        } rows: {
            // 行ごとに「ドラッグされたらファイルとして渡せる」と登録する。
            // 何行か選んでドラッグすると、選んだ行の分がまとめて渡る
            ForEach(items) { item in
                if let drag = dragItem(for: item) {
                    TableRow(item).draggable(drag)
                } else {
                    TableRow(item)
                }
            }
        }
        // 右クリックのメニューと、ダブルクリック・Return（primaryAction）
        .contextMenu(forSelectionType: ListItem.ID.self) { ids in
            if canOpen(ids) {
                Button("開く") { open(ids) }
            }
            if !ids.isEmpty {
                Button("取り出す…") { chooseDestinationAndExtract(ids) }
            }
        } primaryAction: { ids in
            open(ids)
        }
        .focused($tableFocused)
        // スペースキー：選んだファイルを Quick Look で見る（もう一度押すと閉じる）
        .onKeyPress(.space) {
            if quickLookURL != nil {
                quickLookURL = nil
            } else {
                quickLook(selection)
            }
            return .handled
        }
        // ⌫（delete）：上のフォルダへ。Mac の作法では ⌘↑ だが、7-Zip から来た人の BS の癖に合わせて足した。
        // 表は ⌫ を「削除」として先に受け取るので onKeyPress には来ない。表の ⌫ の受け口は onDeleteCommand。
        // 一覧にフォーカスがあるときだけ効く（検索欄などで文字を消すのは邪魔しない）
        .onDeleteCommand {
            goUp()
        }
    }

    /// 今いるフォルダの中身を作り直す
    private func refreshItems() {
        items = DirectoryListing.items(in: currentDir, entries: entries, encoding: encoding)
        selection = []
        // パンくずのボタンではなく一覧を操作の対象にする（矢印キーや Return がすぐ効くように）
        tableFocused = true
    }

    /// 「開く」ができるか：フォルダ 1 つ、またはファイルだけ
    private func canOpen(_ ids: Set<ListItem.ID>) -> Bool {
        let picked = items.filter { ids.contains($0.id) }
        guard !picked.isEmpty else { return false }
        return (picked.count == 1 && picked[0].isDirectory) || picked.allSatisfy { !$0.isDirectory }
    }

    /// ダブルクリック・Return・右クリックの「開く」。
    /// フォルダなら中に入り、ファイルなら一時フォルダに取り出して既定のアプリで開く（7-Zip と同じ）
    private func open(_ ids: Set<ListItem.ID>) {
        guard canOpen(ids) else { return }
        let picked = items.filter { ids.contains($0.id) }
        if picked.count == 1, picked[0].isDirectory {
            enter(picked[0].name)
            return
        }
        // パスワードが要るのにまだ聞いていなければ、聞いてから続ける
        let entryIDs = picked.reduce(into: Set<Int>()) { $0.formUnion($1.entryIDs) }
        if blockedByUnsupportedPassword(entryIDs) { return }
        if needsPassword(entryIDs) {
            askPassword { open(ids) }
            return
        }
        let files = picked.compactMap { dragItem(for: $0) }
        Task {
            for file in files {
                // 取り出しは裏のスレッドで。終わったら既定のアプリで開く（ShellExecute の "open" に当たる）
                let result = await Task.detached { Result { try file.export() } }.value
                switch result {
                case .success(let url):
                    NSWorkspace.shared.open(url)
                case .failure(let error):
                    notice = Notice(title: String(localized: "開けませんでした"), message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - パスワード

    /// その項目を読むのにパスワードが要るのに、まだ聞いていないか（ids が nil なら全部）
    private func needsPassword(_ ids: Set<Int>?) -> Bool {
        guard password == nil, isZip else { return false }
        return entries.contains { $0.isEncrypted && (ids?.contains($0.id) ?? true) }
    }

    /// 解けないパスワード付き（7z・rar など）を読もうとしていれば知らせて true（ids が nil なら全部）
    private func blockedByUnsupportedPassword(_ ids: Set<Int>?) -> Bool {
        guard !isZip, entries.contains(where: { $0.isEncrypted && (ids?.contains($0.id) ?? true) }) else { return false }
        notice = Notice(title: String(localized: "パスワード付きのため取り出せません"),
                        message: String(localized: "パスワードを解けるのは zip だけです。7z・rar などのパスワードには対応していません（一覧は見られます）"))
        return true
    }

    /// パスワードを聞く。合ったら then を続ける
    private func askPassword(then: (() -> Void)?) {
        afterPassword = then
        showingPassword = true
    }

    /// シートで入れられたパスワードを確かめる。合っていれば覚えて、シートを閉じて続きをやる
    private func checkPassword(_ input: String) -> Bool {
        guard let archiveURL, ArchiveReader.checkPassphrase(archiveURL, input) else { return false }
        password = input
        showingPassword = false
        let next = afterPassword
        afterPassword = nil
        // シートが閉じてから続ける（取り出し先を選ぶダイアログなどが重ならないように）
        Task { next?() }
        return true
    }

    /// 選んだファイルを一時フォルダに取り出して、Quick Look で見せる（フォルダは飛ばす）
    private func quickLook(_ ids: Set<ListItem.ID>) {
        let files = items.filter { ids.contains($0.id) && !$0.isDirectory }
        guard !files.isEmpty else { return }
        let entryIDs = files.reduce(into: Set<Int>()) { $0.formUnion($1.entryIDs) }
        if blockedByUnsupportedPassword(entryIDs) { return }
        if needsPassword(entryIDs) {
            askPassword { quickLook(ids) }
            return
        }
        let drags = files.compactMap { dragItem(for: $0) }
        Task {
            var urls: [URL] = []
            for drag in drags {
                if let url = try? await Task.detached(operation: { try drag.export() }).value {
                    urls.append(url)
                }
            }
            guard let first = urls.first else {
                notice = Notice(title: String(localized: "開けませんでした"), message: "")
                return
            }
            quickLookURLs = urls
            quickLookURL = first
        }
    }

    private func enter(_ name: String) {
        currentDir += name + "/"
    }

    private func goUp() {
        var parts = currentDir.split(separator: "/")
        guard !parts.isEmpty else { return }
        parts.removeLast()
        currentDir = parts.map { $0 + "/" }.joined()
    }

    // MARK: - Finder へドラッグして取り出す

    /// 一覧の 1 行をドラッグしたときに渡すもの。ドロップされた場所に「そのまま置く」（設定に関係なく）
    private func dragItem(for item: ListItem) -> DragItem? {
        guard let archiveURL else { return nil }
        // ドロップされたあとではパスワードを聞けないので、まだ聞いていなければドラッグできなくする
        if needsPassword(item.entryIDs) { return nil }
        return DragItem(
            archiveURL: archiveURL,
            ids: item.entryIDs,
            encoding: encoding,
            stripPrefix: currentDir,
            name: item.name,
            passphrase: password
        )
    }

    // MARK: - 取り出す

    /// 取り出し先のフォルダを選んでもらい、取り出す。
    /// picked が空なら書庫の全部、そうでなければ選んだもの（今いるフォルダを起点にする。7-Zip と同じ）
    private func chooseDestinationAndExtract(_ picked: Set<ListItem.ID>) {
        guard let archiveURL else { return }
        let pickedIDs: Set<Int>? = picked.isEmpty ? nil
            : items.filter { picked.contains($0.id) }.reduce(into: Set<Int>()) { $0.formUnion($1.entryIDs) }
        if blockedByUnsupportedPassword(pickedIDs) { return }
        if needsPassword(pickedIDs) {
            askPassword { chooseDestinationAndExtract(picked) }
            return
        }

        // フォルダを選ぶダイアログ（Win32 の IFileOpenDialog に FOS_PICKFOLDERS を付けたもの）。
        // ユーザーがここで選んだフォルダには、サンドボックスの中からでも書き込める
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "ここに取り出す")
        panel.message = extractMessage(items.filter { picked.contains($0.id) })
        panel.directoryURL = archiveURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let encoding = encoding
        let passphrase = password   // 裏のスレッドに渡すので、ここで値を写しておく
        let pickedItems = items.filter { picked.contains($0.id) }
        let ids: Set<Int>? = pickedItems.isEmpty ? nil : pickedItems.reduce(into: Set<Int>()) { $0.formUnion($1.entryIDs) }
        var stripPrefix = pickedItems.isEmpty ? "" : currentDir
        let destination: URL
        let reveal: URL
        if placement == .direct, pickedItems.count == 1, let only = pickedItems.first {
            // 1 つだけ選んで「そのまま置く」：取り出し先に直接置く
            destination = folder
            reveal = folder.appending(path: only.name)
        } else {
            // 取り出すものの、いちばん上の階層の行。全部のときは書庫のいちばん上の中身
            let tops = pickedItems.isEmpty
                ? DirectoryListing.items(in: "", entries: entries, encoding: encoding)
                : pickedItems
            let plan = destinationFolder(in: folder, tops: tops, archiveURL: archiveURL)
            (destination, reveal) = (plan.destination, plan.reveal)
            if let renamed = plan.renamedTop {
                // 「資料」を「資料 2」として置くので、書庫の中の「資料/」は取り除いて「資料 2」の中に書く
                stripPrefix += renamed + "/"
            }
        }

        extracting = true
        Task {
            // 重い処理は裏のスレッドで（WPF の Task.Run に当たる）。終わったらメインスレッドに戻って画面を直す
            let result = await Task.detached {
                Result {
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    return try ArchiveExtractor.extract(archiveURL, ids: ids, encoding: encoding,
                                                        stripPrefix: stripPrefix, passphrase: passphrase,
                                                        to: destination)
                }
            }.value
            extracting = false

            switch result {
            case .success(let r):
                // Finder で取り出した場所を見せる（explorer.exe /select, に当たる）
                if revealAfterExtract {
                    NSWorkspace.shared.activateFileViewerSelecting([reveal])
                }
                if !r.skipped.isEmpty || !r.failed.isEmpty {
                    notice = Notice(title: String(localized: "取り出しました（\(r.written) 個）"), message: summary(r))
                }
            case .failure(let error):
                notice = Notice(title: String(localized: "取り出せませんでした"), message: error.localizedDescription)
            }
        }
    }

    /// 取り出し先を選ぶダイアログの説明。全部なのか選んだものなのかを、決める直前に見せる
    private func extractMessage(_ picked: [ListItem]) -> String {
        if picked.isEmpty {
            let files = entries.filter { !$0.isDirectory }.count
            return String(localized: "書庫の全部（ファイル \(files) 個）を取り出します。取り出し先のフォルダを選んでください")
        }
        let first = picked[0].name
        if picked.count == 1 {
            return String(localized: "「\(first)」を取り出します。取り出し先のフォルダを選んでください")
        }
        return String(localized: "選んだ \(picked.count) 項目（「\(first)」ほか）を取り出します。取り出し先のフォルダを選んでください")
    }

    /// 取り出す先を決める（Mac のアーカイブユーティリティと同じ）。
    /// 中身が 1 つのフォルダにまとまっていればそのまま置き、同じ名前があれば「資料 2」として横に並べる。
    /// そうでなければ書庫の名前のフォルダを作る（「ディズニー/ディズニー/」と二重にしないため）。
    /// renamedTop は「資料 2」にしたときの元の名前（書庫の中のその階層を取り除いて書く）
    private func destinationFolder(in folder: URL, tops: [ListItem], archiveURL: URL)
        -> (destination: URL, reveal: URL, renamedTop: String?) {
        if tops.count == 1, let top = tops.first, top.isDirectory {
            let target = uniqueURL(in: folder, name: top.name)
            if target.lastPathComponent == top.name {
                return (folder, target, nil)
            }
            return (target, target, top.name)
        }

        // 「資料.tar.gz」なら「資料」。同じ名前があれば「資料 2」「資料 3」…
        var base = archiveURL.deletingPathExtension()
        if base.pathExtension.lowercased() == "tar" { base = base.deletingPathExtension() }
        let target = uniqueURL(in: folder, name: base.lastPathComponent)
        return (target, target, nil)
    }

    /// folder の中で name を使える場所。もうあれば「name 2」「name 3」…（Finder と同じ番号の付け方）
    private func uniqueURL(in folder: URL, name: String) -> URL {
        var candidate = folder.appending(path: name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(name) \(n)")
            n += 1
        }
        return candidate
    }

    private func summary(_ r: ExtractResult) -> String {
        var lines: [String] = []
        if !r.skipped.isEmpty {
            lines.append(String(localized: "同じ名前があったので書かなかったもの（\(r.skipped.count) 個）:") + "\n" + r.skipped.prefix(10).joined(separator: "\n"))
        }
        if !r.failed.isEmpty {
            lines.append(String(localized: "取り出せなかったもの（\(r.failed.count) 個）:") + "\n" + r.failed.prefix(10).joined(separator: "\n"))
        }
        return lines.joined(separator: "\n\n")
    }
}

#Preview {
    ContentView()
}
