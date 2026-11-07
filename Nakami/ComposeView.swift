//
//  ComposeView.swift
//  Nakami
//
//  Created by synchrium on 2026/11/01
//
//  Copyright (C) 2026  synchrium
//

import AppKit
import SwiftUI

/// 新しい書庫を作る窓（⌘N）。Finder からファイルやフォルダをドロップして中身を組み立て、
/// 「作る」（⌘S）で書き出す。書き出すまでは実際のファイルを何も書かない。
/// 見た目と操作は書庫を見る窓と同じ（フォルダに入る・⌘↑ や ⌫ で戻る・パンくず）
/// 新しい書庫の窓を開くときに渡すもの。Finder の右クリック（サービス）から来たファイル。
/// id を持たせて毎回違う値にする（同じ値だと、新しい窓ではなく前の窓が前に出るだけになる）
struct ComposeRequest: Codable, Hashable {
    var id = UUID()
    var urls: [URL] = []
    /// 今ある書庫の編集なら、その EditSession の id
    var editID: UUID?
}

struct ComposeView: View {
    /// 窓を開いたときに最初から入れるもの（⌘N なら空）
    var initialURLs: [URL] = []
    /// 今ある書庫の編集なら、その id（新しく作るときは nil）
    var editID: UUID?

    @State private var root = ComposeNode.newFolder("")
    @State private var path: [ComposeNode] = []        // 今いるフォルダまでの道（空ならいちばん上）
    @State private var selection = Set<ComposeNode.ID>()
    @State private var notice: Notice?
    @State private var renaming: ComposeNode?
    @State private var askingPassword = false
    @State private var writing = false

    // ツールバーで切り替える値。窓を開いたときに設定（⌘,）の既定を入れる
    @State private var format: ArchiveFormat = .zip
    @State private var encoding: WriteEncoding = .utf8
    @State private var usePassword = false
    @State private var loadedDefaults = false
    @State private var broughtToFront = false
    /// もう決まっているパスワード（編集している zip の元のパスワード）。あれば保存のたびに聞かない
    @State private var knownPassword: String?
    /// 上書き保存したときにステータスバーに出す一言
    @State private var savedMessage: String?

    @AppStorage(SettingsKey.composeFormat) private var defaultFormat: ArchiveFormat = .zip
    @AppStorage(SettingsKey.composeEncoding) private var defaultEncoding: WriteEncoding = .utf8
    @AppStorage(SettingsKey.composeEncryption) private var encryption: ZipEncryption = .aes256
    @AppStorage(SettingsKey.revealAfterCompose) private var revealAfterCompose = true

    @FocusState private var tableFocused: Bool

    /// 今いるフォルダ
    private var current: ComposeNode { path.last ?? root }

    /// 今ある書庫の編集なら、その情報
    private var session: EditSession? { editID.flatMap(EditSession.session) }

    /// パンくずのいちばん上と窓の題名
    private var rootTitle: String {
        session.map { String(localized: "編集：\($0.archiveURL.lastPathComponent)") } ?? String(localized: "新しい書庫")
    }

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            if current.children.isEmpty {
                ContentUnavailableView(
                    path.isEmpty ? "ここにファイルやフォルダをドロップ" : "空のフォルダ",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Finder から入れたものを、ツールバーの「作る」（⌘S）で書庫にします。フォルダを作る（⇧⌘N）こともできます")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // 空のときは、どこに落としても今いるフォルダへ
                .dropDestination(for: ComposeDrop.self) { drops, _ in
                    receive(drops, into: current)
                    return true
                }
            } else {
                table
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 640, minHeight: 360)
        .navigationTitle(rootTitle)
        .toolbar { toolbarContent }
        .overlay {
            if writing {
                ProgressView(session == nil ? "書庫を作っています…" : "保存しています…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .onAppear {
            guard !loadedDefaults else { return }
            loadedDefaults = true
            if let session {
                // 編集：取り出した中身を読み込み、形式・文字コード・パスワードは元の書庫に合わせる
                format = session.format
                encoding = session.encoding
                knownPassword = session.password
                usePassword = session.password != nil
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: session.folder, includingPropertiesForKeys: nil)) ?? []
                root.children = contents.compactMap { ComposeNode.load($0) }
                // 見る窓に落とされたものがあれば足す（足したものが選ばれた状態になる）
                add(initialURLs, into: root)
            } else {
                format = defaultFormat
                encoding = defaultEncoding
                add(initialURLs, into: root)
            }
            // 最初から中身があれば、一覧にフォーカスを置く（でないとパンくずのボタンに青い枠が付く）
            if !root.children.isEmpty {
                DispatchQueue.main.async {
                    tableFocused = true
                }
            }
        }
        // 編集の窓を閉じたら、取り出した中身を消す
        .onDisappear {
            if let editID { EditSession.close(editID) }
        }
        // パスワードを外したら、引き継いだパスワードも忘れる（もう一度付けるときは新しく聞く）
        .onChange(of: usePassword) {
            if !usePassword { knownPassword = nil }
        }
        // Finder の右クリックから頼まれて起動すると、Nakami は「隠す」（⌘H）の状態で起動することがあり、
        // 窓はできているのに見えない。最初から中身がある窓は、隠すを解いていちばん手前に出す
        .background(WindowReader { window in
            guard !initialURLs.isEmpty, !broughtToFront else { return }
            broughtToFront = true
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        })

        .sheet(item: $renaming) { node in
            RenameSheet(
                original: node.name,
                validate: { validateName($0, for: node) },
                commit: { newName in
                    node.name = newName
                    renaming = nil
                },
                cancel: { renaming = nil }
            )
        }
        .sheet(isPresented: $askingPassword) {
            NewPasswordSheet(
                commit: { password in
                    askingPassword = false
                    knownPassword = password
                    let asCopy = pendingAsCopy
                    // シートが閉じてから保存のダイアログを出す（重ならないように）
                    DispatchQueue.main.async { write(password: password, asCopy: asCopy) }
                },
                cancel: { askingPassword = false }
            )
        }
        .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
               presenting: notice) { _ in
            Button("OK") {}
        } message: { n in
            Text(n.message)
        }
    }

    // MARK: - ツールバー

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("上へ", systemImage: "chevron.left") { goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("上のフォルダへ（⌘↑）")
                .disabled(path.isEmpty)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("新しいフォルダ", systemImage: "folder.badge.plus") { newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("今いるところにフォルダを作る（⇧⌘N）")
            Button("外す", systemImage: "minus.circle") { removeSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .help("選んだものを書庫に入れない（⌘⌫。元のファイルは消えません）")
                .disabled(selection.isEmpty)
            Picker("形式", selection: $format) {
                ForEach(ArchiveFormat.allCases) { Text(verbatim: $0.fileExtension).tag($0) }
            }
            .help(session == nil ? Text("作る書庫の形式") : Text("編集では元の書庫と同じ形式で保存します"))
            .disabled(session != nil)
            Picker("文字コード", selection: $encoding) {
                ForEach(WriteEncoding.allCases) { Text($0.label).tag($0) }
            }
            .help(format.isZip ? Text("ファイル名の文字コード。古い Windows に渡すなら Shift_JIS") : Text("文字コードを選べるのは zip だけです（7z・tar はいつも Unicode）"))
            .disabled(!format.isZip)
            Toggle(isOn: $usePassword) {
                Label("パスワード", systemImage: usePassword && format.isZip ? "lock.fill" : "lock.open")
            }
            .help(format.isZip ? Text("パスワードを付ける（作るときに聞きます）") : Text("パスワードを付けられるのは zip だけです"))
            .disabled(!format.isZip)
            if session != nil {
                Button("別名で保存", systemImage: "square.and.arrow.down.on.square") { create(asCopy: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .help("別の名前で保存する（⇧⌘S。元の書庫はそのまま）")
                    .disabled(root.children.isEmpty || writing)
                Button("保存", systemImage: "square.and.arrow.down") { create(asCopy: false) }
                    .keyboardShortcut("s")
                    .help("元の書庫に上書きする（⌘S。最初の保存のとき、元の書庫はゴミ箱に入ります）")
                    .disabled(root.children.isEmpty || writing)
            } else {
                Button("作る", systemImage: "archivebox") { create(asCopy: true) }
                    .keyboardShortcut("s")
                    .help("書庫を作る（⌘S）")
                    .disabled(root.children.isEmpty || writing)
            }
        }
    }

    // MARK: - 一覧とフォルダの移動

    private var pathBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // パンくずに落とすと、その階層へ動かす（上のフォルダへ戻すのに使う）
                Button { path = [] } label: {
                    Label(rootTitle, systemImage: session == nil ? "archivebox" : "doc.zipper")
                }
                .dropDestination(for: ComposeDrop.self) { drops, _ in
                    receive(drops, into: root)
                    return true
                }
                ForEach(path.indices, id: \.self) { i in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button(path[i].name) { path = Array(path[...i]) }
                        .dropDestination(for: ComposeDrop.self) { drops, _ in
                            receive(drops, into: path[i])
                            return true
                        }
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private var table: some View {
        Table(of: ComposeNode.self, selection: $selection) {
            TableColumn("名前") { node in
                Label(node.name, systemImage: node.isFolder ? "folder" : (node.linkTarget != nil ? "arrow.up.right.square" : "doc"))
            }
            TableColumn("サイズ") { node in
                Text(node.totalSize.formatted(.byteCount(style: .file)))
                    .monospacedDigit()
                    .foregroundStyle(node.isFolder ? .secondary : .primary)
            }
            .width(min: 60, ideal: 90)
            TableColumn("更新日時") { node in
                Text(node.modified?.formatted(date: .numeric, time: .shortened) ?? "")
            }
            .width(min: 100, ideal: 140)
        } rows: {
            ForEach(current.sortedChildren) { node in
                if node.isFolder {
                    TableRow(node)
                        .draggable(ComposeDragItem(id: node.id, tree: node.exportTree))
                        .dropDestination(for: ComposeDrop.self) { drops in
                            receive(drops, into: node)
                        }
                } else {
                    TableRow(node)
                        .draggable(ComposeDragItem(id: node.id, tree: node.exportTree))
                }
            }
            // 行と行の間（と下の空いているところ）に落としたら、今いるフォルダへ。
            // 本来は並べ替えの位置を受け取る受け口だが、位置は使わない（一覧はいつも名前の順）
            .dropDestination(for: ComposeDrop.self) { index, drops in
                receive(drops, into: current)
            }
        }
        .contextMenu(forSelectionType: ComposeNode.ID.self) { ids in
            if ids.count == 1, let node = node(for: ids.first) {
                if node.isFolder {
                    Button("開く") { enter(node) }
                }
                Button("名前を変える…") { renaming = node }
            }
            if !ids.isEmpty {
                Button("外す") { remove(ids) }
            }
        } primaryAction: { ids in
            if ids.count == 1, let node = node(for: ids.first), node.isFolder {
                enter(node)
            }
        }
        .focused($tableFocused)
        // ⌫ で上のフォルダへ（書庫を見る窓と同じ）。外すのは ⌘⌫
        .onDeleteCommand { goUp() }
    }

    private var statusBar: some View {
        HStack {
            Text("ファイル \(root.fileCount) 個・\(root.totalSize.formatted(.byteCount(style: .file)))")
            if let savedMessage {
                Text(savedMessage)
                    .foregroundStyle(.green)
            }
            Spacer()
            Text("Mac のゴミ（`.DS_Store`・`__MACOSX`・`._` で始まるもの）は入れません")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func node(for id: ComposeNode.ID?) -> ComposeNode? {
        current.children.first { $0.id == id }
    }

    private func enter(_ node: ComposeNode) {
        path.append(node)
        selection = []
    }

    private func goUp() {
        guard !path.isEmpty else { return }
        let left = path.removeLast()
        // 出てきたフォルダを選んでおく（Finder と同じ）
        selection = [left.id]
    }

    // MARK: - 組み立てる

    /// Finder から来たものを folder に入れる。同じ名前があれば「名前 2」にする
    private func add(_ urls: [URL], into folder: ComposeNode) {
        var added: [ComposeNode] = []
        for url in urls {
            guard let node = ComposeNode.load(url) else { continue }
            node.name = folder.uniqueName(node.name, isFolder: node.isFolder)
            folder.children.append(node)
            added.append(node)
        }
        if folder === current {
            selection = Set(added.map(\.id))
        }
    }

    /// フォルダの行やパンくずに落とされたもの。Finder からのファイルは入れ、窓の中の項目は動かす
    private func receive(_ drops: [ComposeDrop], into target: ComposeNode) {
        var urls: [URL] = []
        var ids: [UUID] = []
        for drop in drops {
            switch drop {
            case .file(let url): urls.append(url)
            case .item(let id, let copy):
                ids.append(id)
                // 窓の中の移動ではコピーは要らないので捨てる（…/ComposeDrag/ランダム/ を丸ごと）
                try? FileManager.default.removeItem(at: copy.deletingLastPathComponent().deletingLastPathComponent())
            }
        }
        if !urls.isEmpty { add(urls, into: target) }
        move(ids, into: target)
    }

    /// 窓の中の項目を target の中へ動かす。同じ名前があれば「名前 2」にする
    private func move(_ ids: [UUID], into target: ComposeNode) {
        for id in ids {
            guard let (parent, node) = root.findWithParent(id),
                  parent !== target,                         // もうそこにある
                  node !== target, !node.contains(target)    // フォルダを自分の中へは動かせない
            else { continue }
            parent.children.removeAll { $0 === node }
            node.name = target.uniqueName(node.name, isFolder: node.isFolder)
            target.children.append(node)
            selection.remove(id)
        }
    }

    private func newFolder() {
        let folder = ComposeNode.newFolder(current.uniqueName(String(localized: "名称未設定フォルダ"), isFolder: true))
        current.children.append(folder)
        selection = [folder.id]
        // すぐ名前を打てるようにする（Finder と同じ）
        renaming = folder
    }

    private func removeSelected() {
        remove(selection)
    }

    private func remove(_ ids: Set<ComposeNode.ID>) {
        current.children.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    private func validateName(_ name: String, for node: ComposeNode) -> String? {
        if name.isEmpty { return String(localized: "名前を入れてください") }
        if name.contains("/") { return String(localized: "「/」は名前に使えません") }
        if name == "." || name == ".." { return String(localized: "この名前は使えません") }
        if current.hasChild(named: name, excluding: node) { return String(localized: "同じ名前がもうあります") }
        return nil
    }

    // MARK: - 書き出す

    /// パスワードを聞いている間、そのあと別名で保存するのか上書きするのかを覚えておく
    @State private var pendingAsCopy = true

    /// 作る・保存する。asCopy が true なら保存のダイアログで場所と名前を聞く（新しく作るときもこちら）。
    /// false なら編集している書庫に上書きする
    private func create(asCopy: Bool) {
        savedMessage = nil
        if usePassword && format.isZip {
            if let knownPassword {
                // 編集している zip の元のパスワード（か、この窓で一度入れたもの）をそのまま使う
                write(password: knownPassword, asCopy: asCopy)
            } else {
                pendingAsCopy = asCopy
                askingPassword = true
            }
        } else {
            write(password: nil, asCopy: asCopy)
        }
    }

    private func write(password: String?, asCopy: Bool) {
        if asCopy {
            chooseAndWrite(password: password)
        } else if let session {
            saveInPlace(session, password: password)
        }
    }

    /// 保存の場所と名前を聞いて、書庫を書く
    private func chooseAndWrite(password: String?) {
        // 保存のダイアログ（Win32 の IFileSaveDialog に当たる）。
        // ユーザーがここで決めた場所には、サンドボックスの中からでも書ける
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName() + "." + format.fileExtension
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.prompt = session == nil ? String(localized: "作る") : String(localized: "保存")
        panel.message = String(localized: "書庫の名前と保存する場所を決めてください")
        if let session {
            panel.directoryURL = session.archiveURL.deletingLastPathComponent()
        } else if let first = root.children.compactMap(\.source).first {
            panel.directoryURL = first.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let plan = root.plan()
        let options = writeOptions(password: password)
        writing = true
        Task {
            let result = await Task.detached {
                Result { try ArchiveWriter.write(plan, to: url, options: options) }
            }.value
            writing = false
            switch result {
            case .success(let r):
                if revealAfterCompose {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                showWarnings(r)
                // 別名で保存した先が、どこかの見る窓で開いている書庫なら読み直してもらう
                NotificationCenter.default.post(name: .archiveDidChange, object: url)
            case .failure(let error):
                notice = Notice(title: String(localized: "作れませんでした"), message: error.localizedDescription)
            }
        }
    }

    /// 編集している書庫に上書きする。新しい書庫を一時ファイルに書き終えてから置き換えるので、
    /// 書いている途中で失敗しても元の書庫は壊れない
    private func saveInPlace(_ session: EditSession, password: String?) {
        let plan = root.plan()
        let options = writeOptions(password: password)
        let temp = EditSession.newFolder().appending(path: session.archiveURL.lastPathComponent)
        writing = true
        Task {
            let result = await Task.detached {
                Result {
                    try FileManager.default.createDirectory(at: temp.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    return try ArchiveWriter.write(plan, to: temp, options: options)
                }
            }.value
            defer { try? FileManager.default.removeItem(at: temp.deletingLastPathComponent()) }
            writing = false
            switch result {
            case .success(let r):
                do {
                    let first = !session.backedUp
                    try session.replace(with: temp)
                    savedMessage = first
                        ? String(localized: "保存しました（元の書庫はゴミ箱に入れました）")
                        : String(localized: "保存しました")
                    showWarnings(r)
                    NotificationCenter.default.post(name: .archiveDidChange, object: session.archiveURL)
                } catch {
                    notice = Notice(title: String(localized: "保存できませんでした"), message: error.localizedDescription)
                }
            case .failure(let error):
                notice = Notice(title: String(localized: "保存できませんでした"), message: error.localizedDescription)
            }
        }
    }

    private func writeOptions(password: String?) -> WriteOptions {
        // 編集している zip にパスワードが付いていて、それを引き継ぐときは方式も元のまま。
        // 新しく付けるときは設定（⌘,）の方式
        let method = (knownPassword != nil && knownPassword == session?.password ? session?.encryption : nil) ?? encryption
        return WriteOptions(format: format, encoding: encoding, encryption: method,
                            password: format.isZip ? password : nil)
    }

    private func showWarnings(_ r: WriteResult) {
        guard !r.warnings.isEmpty else { return }
        notice = Notice(
            title: String(localized: "作りました（気をつけること \(r.warnings.count) 件）"),
            message: String(localized: "Shift_JIS で表せない字は「?」になりました:") + "\n"
                + r.warnings.prefix(10).joined(separator: "\n"))
    }

    /// 書庫の名前の候補。編集なら元の書庫の名前、1 つだけ入れたならその名前、
    /// 何個かなら「アーカイブ」（アーカイブユーティリティと同じ）
    private func defaultName() -> String {
        if let session {
            var base = session.archiveURL.deletingPathExtension()
            if base.pathExtension.lowercased() == "tar" { base = base.deletingPathExtension() }
            return base.lastPathComponent
        }
        return root.children.count == 1 ? root.children[0].name : String(localized: "アーカイブ")
    }
}

/// SwiftUI の窓の中から、その窓（AppKit の NSWindow）を受け取る。
/// 見えない小さな NSView を置き、それが窓に入ったときに呼ぶ（WPF の Window.GetWindow(this) に近い）
struct WindowReader: NSViewRepresentable {
    let action: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowReaderView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class WindowReaderView: NSView {
        var action: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in self?.action?(window) }
        }
    }
}
