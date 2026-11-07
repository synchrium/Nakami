//
//  ArchiveExtractor.swift
//  Nakami
//
//  Created by synchrium on 2026/10/31
//
//  Copyright (C) 2026  synchrium
//

import Foundation
import CArchive

/// 取り出しの結果
nonisolated struct ExtractResult: Sendable {
    var written = 0             // 書き出したファイルの数
    var skipped: [String] = []  // 同じ名前があったので書かなかったもの
    var failed: [String] = []   // 書き出せなかったもの（パスワード付きなど）
}

/// libarchive で書庫から取り出す
nonisolated enum ArchiveExtractor {
    /// ids の項目を destination の中に取り出す（ids が nil なら全部）。
    /// 書庫の中のパス（フォルダ）はそのまま作る。ただし stripPrefix で始まるパスはそれを取り除く
    /// （「資料/a.txt」だけを「そのまま置く」ときは stripPrefix に「資料/」を渡す）。
    /// 同じ名前のファイルがあれば上書きしない
    static func extract(_ url: URL, ids: Set<Int>?, encoding: NameEncoding, stripPrefix: String = "",
                        passphrase: String? = nil, to destination: URL) throws -> ExtractResult {
        // 取り出し先そのものまでのパスにシンボリックリンクがあると（/tmp → /private/tmp など）、
        // 下の SECURE_SYMLINKS が全部を「危ない」として書かない。取り出し先はユーザーが選んだ場所なので、
        // 先に本当のパスにしておく（書庫の中のリンクを通って外へ書くのは、取り出し先の中では今までどおり防ぐ）
        let destination = realPath(destination)
        let reader = try ArchiveReader.openForRead(url, passphrase: passphrase)
        defer { archive_read_free(reader) }

        // 書き出し側もハンドル。archive_write_disk は「ディスクにファイルを作る」書き出し先
        guard let writer = archive_write_disk_new() else {
            throw ArchiveError.failed(String(localized: "libarchive の初期化に失敗しました"))
        }
        defer { archive_write_free(writer) }
        archive_write_disk_set_options(writer,
            ARCHIVE_EXTRACT_TIME              // 更新日時を書庫のとおりにする
            | ARCHIVE_EXTRACT_NO_OVERWRITE    // 同じ名前のファイルがあれば上書きしない
            | ARCHIVE_EXTRACT_SECURE_SYMLINKS // シンボリックリンクをたどって外に書かない
            | ARCHIVE_EXTRACT_SECURE_NODOTDOT // 「..」を含むパスには書かない
        )

        var result = ExtractResult()
        var entry: OpaquePointer?
        var index = 0
        while true {
            let r = archive_read_next_header(reader, &entry)
            if r == ARCHIVE_EOF { break }
            if r < ARCHIVE_WARN { throw ArchiveError.failed(ArchiveReader.errorString(reader)) }
            guard let entry else { break }
            defer { index += 1 }

            // 一覧のときと同じ順番で読むので、順番（index）が ArchiveEntry.id と一致する
            guard ids?.contains(index) ?? true else {
                archive_read_data_skip(reader)
                continue
            }

            let item = ArchiveReader.makeEntry(entry, id: index)
            let relative = strip(item.safePath(encoding), stripPrefix)
            if relative.isEmpty {
                archive_read_data_skip(reader)
                continue
            }
            let target = destination.appending(path: relative)

            if !item.isDirectory && FileManager.default.fileExists(atPath: target.path) {
                result.skipped.append(relative)
                archive_read_data_skip(reader)
                continue
            }

            // 書き出す先のパスを、表示しているのと同じ文字コードで読んだ名前に差し替える。
            // こうしないと Shift_JIS の名前が化けたままディスクにできてしまう
            archive_entry_copy_pathname(entry, target.path)
            if let link = archive_entry_hardlink(entry) {
                // ハードリンクの元も同じように差し替える（tar で使われる）
                let linkItem = ArchiveEntry(id: -1, rawName: Array(UnsafeRawBufferPointer(start: link, count: strlen(link))),
                                            utf8Name: nil, size: 0, modified: nil, isDirectory: false)
                archive_entry_copy_hardlink(entry, destination.appending(path: strip(linkItem.safePath(encoding), stripPrefix)).path)
            }

            guard archive_write_header(writer, entry) >= ARCHIVE_WARN else {
                result.failed.append(relative)
                archive_read_data_skip(reader)
                continue
            }
            if archive_entry_size(entry) > 0 && !copyData(from: reader, to: writer) {
                result.failed.append(relative)
                // パスワードが違うときなどは、中身の無いファイルが残るので消す
                archive_write_finish_entry(writer)
                try? FileManager.default.removeItem(at: target)
                continue
            } else if !item.isDirectory {
                result.written += 1
            }
            archive_write_finish_entry(writer)
        }
        return result
    }

    /// リンクを解いた本当のパス。URL の resolvingSymlinksInPath は「/private/tmp」の「/private」を
    /// わざわざ外して「/tmp」に戻すので、C の realpath を使う
    private static func realPath(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    private static func strip(_ path: String, _ prefix: String) -> String {
        // 取り除くフォルダそのもの（「資料/」に対する「資料」）は空にする（作らない）
        if !prefix.isEmpty && path + "/" == prefix { return "" }
        return prefix.isEmpty || !path.hasPrefix(prefix) ? path : String(path.dropFirst(prefix.count))
    }

    /// 中身を少しずつ読んで書く。失敗したら false（パスワード付きの zip など）
    private static func copyData(from reader: OpaquePointer, to writer: OpaquePointer) -> Bool {
        var buffer: UnsafeRawPointer?
        var size = 0
        var offset: la_int64_t = 0
        while true {
            let r = archive_read_data_block(reader, &buffer, &size, &offset)
            if r == ARCHIVE_EOF { return true }
            if r < ARCHIVE_WARN { return false }
            if let buffer, archive_write_data_block(writer, buffer, size, offset) < Int(ARCHIVE_WARN) {
                return false
            }
        }
    }
}
