//
//  DragExport.swift
//  Nakami
//
//  Created by synchrium on 2026/10/31
//
//  Copyright (C) 2026  synchrium
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Nakami の一時フォルダの親（/var/folders/…/T/io.github.synchrium.Nakami）。
/// サンドボックスの外では temporaryDirectory がユーザーの全アプリで共通なので（Windows の %TEMP% と同じ）、
/// 起動時に中を消しても、ほかのアプリのものを消さないよう、Nakami 専用のフォルダを挟む
nonisolated enum AppTemp {
    static let root = FileManager.default.temporaryDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "io.github.synchrium.Nakami", directoryHint: .isDirectory)
}

/// 一覧から Finder へのドラッグで渡すもの（1 行分）。
/// ドラッグを始めた時点では何も書き出さず、ドロップされてから一時フォルダに取り出して Finder に渡す
/// （Windows の仮想ファイルのドラッグ、CFSTR_FILEDESCRIPTOR と CFSTR_FILECONTENTS に当たる）。
/// Finder に渡す処理は裏のスレッドで呼ばれるので、メインスレッドの外（nonisolated）に置く
nonisolated struct DragItem: Transferable, Sendable {
    let archiveURL: URL
    let ids: Set<Int>
    let encoding: NameEncoding
    let stripPrefix: String
    let name: String
    var passphrase: String?

    /// ドラッグ用の一時フォルダ（macOS がそのうち片付ける）
    static let root = AppTemp.root.appending(path: "Drag", directoryHint: .isDirectory)

    /// Transferable：「この型はこういう形で渡せる」という宣言（.NET の IDataObject の形式の一覧に近い）。
    /// ここではファイルとして渡す。中の処理はドロップされてから呼ばれる
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .item) { item in
            SentTransferredFile(try item.export(), allowAccessingOriginalFile: true)
        }
        .suggestedFileName { $0.name }
    }

    /// 一時フォルダに取り出して、そのファイル（フォルダ）の場所を返す
    func export() throws -> URL {
        // ドラッグごとに別の一時フォルダを作り、そこに取り出す
        let folder = Self.root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let result = try ArchiveExtractor.extract(archiveURL, ids: ids, encoding: encoding,
                                                  stripPrefix: stripPrefix, passphrase: passphrase, to: folder)
        if let failed = result.failed.first {
            throw ArchiveError.failed(String(localized: "取り出せませんでした") + ": " + failed)
        }
        return folder.appending(path: name)
    }
}
