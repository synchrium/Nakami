//
//  ComposeModel.swift
//  Nakami
//
//  Created by synchrium on 2026/11/01
//
//  Copyright (C) 2026  synchrium
//

import CoreTransferable
import Foundation
import Observation
import UniformTypeIdentifiers

/// Finder へ書き出すための控え（何をどこからコピーするか）。ドラッグを始めたときに作って一緒に運ぶので、
/// 書き出すときにメインスレッドの項目を見に戻らない（戻ると、ドロップを待つメインスレッドと待ち合って固まる）
nonisolated struct ExportTree: Sendable {
    let name: String
    let isFolder: Bool
    let source: URL?
    let linkTarget: String?
    let children: [ExportTree]

    /// url にコピーを作る（フォルダは中身ごと。窓の中で作ったフォルダも本物にする）
    func copy(to url: URL) throws {
        let fm = FileManager.default
        if isFolder {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            for child in children {
                try child.copy(to: url.appending(path: child.name))
            }
        } else if let linkTarget {
            try fm.createSymbolicLink(atPath: url.path, withDestinationPath: linkTarget)
        } else if let source {
            try fm.copyItem(at: source, to: url)
        }
    }
}

/// 新しい書庫の窓の行をドラッグするときに渡すもの（渡す専用）。
/// Transferable はドラッグ＆ドロップやコピーで渡せる型の印（OLE の IDataObject と、その形式の一覧に当たる）。
/// 渡すのは本物のファイルのコピーだけ。Finder に落とせばそれがそのまま置かれる。
/// Nakami の中に落とされたときは、コピーの場所（…/ComposeDrag/ランダム/項目の id/名前）から
/// 窓の中の項目だとわかるので、コピーは捨てて項目を動かす。
/// （前は id を JSON にして一緒に渡していたが、Finder がその JSON を「Nakami Compose Item」という
/// ファイルにしてしまい、本物のコピーを先に並べても直らなかった）
nonisolated struct ComposeDragItem: Transferable {
    let id: UUID
    let tree: ExportTree

    /// コピーを作る場所の親。アプリの起動時に空にする
    static var root: URL {
        AppTemp.root.appending(path: "ComposeDrag", directoryHint: .isDirectory)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .item) { item in
            // 1 回のドラッグで何度か呼ばれることがあるので、毎回別の場所に作る。
            // APFS ではコピーがクローン（中身を共有するコピー）になるので、大きくても一瞬で済む
            let folder = root
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
                .appending(path: item.id.uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: item.tree.name)
            try item.tree.copy(to: url)
            return SentTransferredFile(url, allowAccessingOriginalFile: true)
        }
    }

    /// Nakami の窓の中からドラッグされたコピーなら、その項目の id
    static func internalID(of url: URL) -> UUID? {
        let parts = url.standardizedFileURL.pathComponents
        guard let i = parts.lastIndex(of: "ComposeDrag"), parts.count == i + 4 else { return nil }
        return UUID(uuidString: parts[i + 2])
    }
}

/// 新しい書庫の窓に落とされるもの（受け取る専用）。窓の中の項目（動かす）か、Finder から来たファイル（入れる）
nonisolated enum ComposeDrop: Transferable {
    case item(UUID, copy: URL)
    case file(URL)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (url: URL) in
            if let id = ComposeDragItem.internalID(of: url) {
                return ComposeDrop.item(id, copy: url)
            }
            return ComposeDrop.file(url)
        })
    }
}

/// 新しい書庫に入れるものの木（フォルダとファイル）。
/// 「作る」を押すまでは実際のファイルを何も書かず、この木を組み立てるだけ。
/// Finder から入れたフォルダは中身まで木にするので、中に入って外したり名前を変えたりできる。
/// @Observable は、値が変わると画面が自動で描き直される印（WPF の INotifyPropertyChanged に当たる）
@Observable
final class ComposeNode: Identifiable {
    let id = UUID()
    var name: String
    let isFolder: Bool
    /// Finder から入れたファイルの場所（窓の中で作ったフォルダは nil）
    let source: URL?
    /// シンボリックリンクなら、指している先
    let linkTarget: String?
    let fileSize: Int64
    let executable: Bool
    let modified: Date?
    var children: [ComposeNode] = []

    init(name: String, isFolder: Bool, source: URL? = nil, linkTarget: String? = nil,
         fileSize: Int64 = 0, executable: Bool = false, modified: Date? = nil) {
        self.name = name
        self.isFolder = isFolder
        self.source = source
        self.linkTarget = linkTarget
        self.fileSize = fileSize
        self.executable = executable
        self.modified = modified
    }

    /// Finder へ書き出すための控え
    var exportTree: ExportTree {
        ExportTree(name: name, isFolder: isFolder, source: source, linkTarget: linkTarget,
                   children: children.map(\.exportTree))
    }

    /// 窓の中で作る、空のフォルダ
    static func newFolder(_ name: String) -> ComposeNode {
        ComposeNode(name: name, isFolder: true, modified: Date())
    }

    /// 大きさ（フォルダなら中身の合計）
    var totalSize: Int64 {
        isFolder ? children.reduce(0) { $0 + $1.totalSize } : fileSize
    }

    /// ファイルの数（フォルダなら中身の数）
    var fileCount: Int {
        isFolder ? children.reduce(0) { $0 + $1.fileCount } : 1
    }

    /// 一覧に出す順（フォルダが先、名前は Finder と同じ並べ方）
    var sortedChildren: [ComposeNode] {
        children.sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Finder から入れる

    /// Finder から来たファイルやフォルダを木にする。Mac のゴミ（.DS_Store など）なら nil
    static func load(_ url: URL) -> ComposeNode? {
        let name = url.lastPathComponent
        guard !ArchiveWriter.isJunk(name) else { return nil }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                                         .contentModificationDateKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }

        if v.isSymbolicLink == true {
            let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? ""
            return ComposeNode(name: name, isFolder: false, linkTarget: target, modified: v.contentModificationDate)
        }
        if v.isDirectory == true {
            let folder = ComposeNode(name: name, isFolder: true, source: url, modified: v.contentModificationDate)
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: Array(keys))) ?? []
            folder.children = contents.compactMap { load($0) }
            return folder
        }
        return ComposeNode(name: name, isFolder: false, source: url,
                           fileSize: Int64(v.fileSize ?? 0),
                           executable: hasExecuteBit(url),
                           modified: v.contentModificationDate)
    }

    /// ファイルの権限に実行の印（x）があるか。
    /// isExecutableKey は「このアプリが今実行してよいか」を答えるので、サンドボックスの中で取り出した
    /// （quarantine の付いた）スクリプトだと false になり、書庫に入れると x が消えてしまう
    private static func hasExecuteBit(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return permissions & 0o111 != 0
    }

    // MARK: - 探す

    /// id の項目と、それが入っているフォルダを探す（この下の全部から）
    func findWithParent(_ id: UUID) -> (parent: ComposeNode, node: ComposeNode)? {
        for child in children {
            if child.id == id { return (self, child) }
            if let found = child.findWithParent(id) { return found }
        }
        return nil
    }

    /// other がこの下（中身の中身も）にあるか
    func contains(_ other: ComposeNode) -> Bool {
        children.contains { $0 === other || $0.contains(other) }
    }

    // MARK: - 名前

    /// この中に name が無ければそのまま、あれば「name 2」「name 3」…（Finder と同じ）。
    /// ファイルは拡張子の前に番号を付ける（「表 2.csv」）。大文字と小文字は同じとみなす（Mac と Windows のファイル名と同じ）
    func uniqueName(_ name: String, isFolder: Bool, excluding: ComposeNode? = nil) -> String {
        guard hasChild(named: name, excluding: excluding) else { return name }
        let ext = isFolder ? "" : (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !hasChild(named: candidate, excluding: excluding) { return candidate }
            n += 1
        }
    }

    func hasChild(named name: String, excluding: ComposeNode? = nil) -> Bool {
        children.contains { $0 !== excluding && $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    // MARK: - 書き出す

    /// 書き出す順に平らにする（フォルダの項目を先に、その中身をあとに）
    func plan(prefix: String = "") -> [PlanItem] {
        children.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.flatMap { child -> [PlanItem] in
            let path = prefix + child.name
            if child.isFolder {
                return [PlanItem(path: path, kind: .folder, modified: child.modified)]
                    + child.plan(prefix: path + "/")
            }
            if let target = child.linkTarget {
                return [PlanItem(path: path, kind: .symlink(target), modified: child.modified)]
            }
            guard let source = child.source else { return [] }
            return [PlanItem(path: path, kind: .file(source, size: child.fileSize, executable: child.executable),
                             modified: child.modified)]
        }
    }
}
