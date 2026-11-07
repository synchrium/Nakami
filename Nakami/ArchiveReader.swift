//
//  ArchiveReader.swift
//  Nakami
//
//  Created by synchrium on 2026/10/31
//
//  Copyright (C) 2026  synchrium
//

import Foundation
import CArchive

// このプロジェクトは何も書かなければメインスレッド（MainActor）で動く設定。
// 書庫を読む・取り出す処理は裏のスレッドでも動かすので、ここの型には nonisolated を付けておく

/// ファイル名の文字コード（ユーザーが切り替える）
nonisolated enum NameEncoding: String, CaseIterable, Identifiable, Sendable {
    case auto = "自動"
    case shiftJIS = "Shift_JIS"
    case utf8 = "UTF-8"

    var id: Self { self }

    /// 画面に出す名前（rawValue は設定の保存に使うので、表示はこちら。英語の画面では訳が出る）
    var label: LocalizedStringResource {
        switch self {
        case .auto: "自動"
        case .shiftJIS: "Shift_JIS"
        case .utf8: "UTF-8"
        }
    }
}

/// 書庫の中の 1 項目（ファイルかフォルダ）
nonisolated struct ArchiveEntry: Identifiable, Sendable {
    let id: Int             // 書庫の中での順番
    let rawName: [UInt8]    // 書庫に書いてある名前のバイト列
    let utf8Name: String?   // libarchive が UTF-8 にできた名前（できなければ nil）
    let size: Int64         // 展開後のサイズ
    let modified: Date?
    let isDirectory: Bool
    var isEncrypted = false // パスワード付きか

    /// 書庫の中のパス（例: "docs/readme.txt"）。文字コードを切り替えても書庫を読み直さずに済むよう、
    /// バイト列を持っておいて表示のたびに文字列にする
    func path(_ encoding: NameEncoding) -> String {
        switch encoding {
        case .auto:
            // UTF-8 の印がある zip や tar・ASCII だけの名前は libarchive が UTF-8 にしてくれる。
            // 印が無い名前は、UTF-8 として正しければ UTF-8（昔の Mac の zip など）、でなければ Shift_JIS
            if let utf8Name { return utf8Name }
            if let s = String(validating: rawName, as: UTF8.self) { return s }
            return NameDecoder.shiftJIS(rawName)
        case .shiftJIS:
            return NameDecoder.shiftJIS(rawName)
        case .utf8:
            return String(decoding: rawName, as: UTF8.self)
        }
    }

    /// 取り出すときのパス。「..」や先頭の「/」を取り除き、取り出し先の外に書き出さないようにする
    /// （悪意のある書庫が「../../.zshrc」のような名前で上書きを狙うのを防ぐ）
    func safePath(_ encoding: NameEncoding) -> String {
        path(encoding)
            .split(separator: "/")
            .filter { $0 != "." && $0 != ".." }
            .joined(separator: "/")
    }
}

nonisolated enum NameDecoder {
    /// Shift_JIS（Windows の CP932。NEC の ① や ㈱ なども含む）として読む
    static func shiftJIS(_ bytes: [UInt8]) -> String {
        let cp932 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        let fixed = restoreBackslash(bytes)
        return String(data: Data(fixed), encoding: cp932)
            ?? String(decoding: fixed, as: UTF8.self)
    }

    /// libarchive は UTF-8 でない zip の名前の「\」（0x5C）を Windows のパス区切りとみなして「/」に変える。
    /// Shift_JIS では「表」「ソ」「能」などの 2 バイト目が 0x5C なので、それまで「/」になってしまう。
    /// 「/」（0x2F）は Shift_JIS の 2 バイト目に来ない値なので、1 バイト目の直後の「/」は元の 0x5C に戻す
    static func restoreBackslash(_ bytes: [UInt8]) -> [UInt8] {
        var out = bytes
        var i = 0
        while i < out.count {
            let b = out[i]
            let isLeadByte = (0x81...0x9F).contains(b) || (0xE0...0xFC).contains(b)
            if isLeadByte && i + 1 < out.count {
                if out[i + 1] == 0x2F { out[i + 1] = 0x5C }
                i += 2
            } else {
                i += 1
            }
        }
        return out
    }
}

/// 書庫を開いた結果
nonisolated struct ArchiveListing: Sendable {
    let entries: [ArchiveEntry]
    let isZip: Bool     // パスワードを解けるのは zip だけ（libarchive が 7z・rar の暗号に対応していない）
}

nonisolated enum ArchiveError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

/// libarchive で書庫を読む
nonisolated enum ArchiveReader {
    /// 書庫の中身の一覧を返す（中身は展開しない）
    static func list(_ url: URL) throws -> ArchiveListing {
        let a = try openForRead(url)
        defer { archive_read_free(a) }

        var entries: [ArchiveEntry] = []
        var isZip = false
        var entry: OpaquePointer?
        while true {
            let r = archive_read_next_header(a, &entry)
            if r == ARCHIVE_EOF { break }
            if r < ARCHIVE_WARN { throw ArchiveError.failed(errorString(a)) }
            guard let entry else { break }

            entries.append(makeEntry(entry, id: entries.count))
            isZip = archive_format(a) & ARCHIVE_FORMAT_BASE_MASK == ARCHIVE_FORMAT_ZIP
            // 中身は読まずに次の項目へ
            archive_read_data_skip(a)
        }
        return ArchiveListing(entries: entries, isZip: isZip)
    }

    /// パスワードが合っているか。パスワード付きの最初の項目を少しだけ読んでみる
    static func checkPassphrase(_ url: URL, _ passphrase: String) -> Bool {
        guard let a = try? openForRead(url, passphrase: passphrase) else { return false }
        defer { archive_read_free(a) }
        var entry: OpaquePointer?
        while archive_read_next_header(a, &entry) == ARCHIVE_OK, let entry {
            guard archive_entry_is_encrypted(entry) != 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 1024)
            return archive_read_data(a, &buffer, buffer.count) >= 0
        }
        return false
    }

    /// libarchive の項目（archive_entry）から ArchiveEntry を作る
    static func makeEntry(_ entry: OpaquePointer, id: Int) -> ArchiveEntry {
        ArchiveEntry(
            id: id,
            // アプリは C ロケールで動くので、UTF-8 の印が無い名前は変換されずにバイト列のまま来る
            rawName: bytes(archive_entry_pathname(entry)),
            utf8Name: archive_entry_pathname_utf8(entry).map { String(cString: $0) },
            size: archive_entry_size(entry),
            modified: archive_entry_mtime_is_set(entry) != 0
                ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry)))
                : nil,
            isDirectory: archive_entry_filetype(entry) == S_IFDIR,
            isEncrypted: archive_entry_is_encrypted(entry) != 0
        )
    }

    /// 書庫を読む準備をする。使い終わったら archive_read_free で閉じる
    static func openForRead(_ url: URL, passphrase: String? = nil) throws -> OpaquePointer {
        // archive_read_new は Win32 の CreateFile のようにハンドル（OpaquePointer）を返す。
        // 使い終わったら archive_read_free で閉じる（CloseHandle に当たる）
        guard let a = archive_read_new() else {
            throw ArchiveError.failed(String(localized: "libarchive の初期化に失敗しました"))
        }
        archive_read_support_filter_all(a)  // gzip・xz などの圧縮
        archive_read_support_format_all(a)  // zip・7z・tar などの形式
        if let passphrase {
            archive_read_add_passphrase(a, passphrase)  // パスワード付きの zip を読むため
        }
        guard archive_read_open_filename(a, url.path, 64 * 1024) == ARCHIVE_OK else {
            let message = errorString(a)
            archive_read_free(a)
            throw ArchiveError.failed(message)
        }
        return a
    }

    /// C の文字列（char *）を、文字列にせずバイト列のまま取り出す
    private static func bytes(_ p: UnsafePointer<CChar>?) -> [UInt8] {
        guard let p else { return [] }
        return Array(UnsafeRawBufferPointer(start: p, count: strlen(p)))
    }

    static func errorString(_ a: OpaquePointer) -> String {
        if let s = archive_error_string(a) {
            let message = String(cString: s)
            // 7z などでファイル名の一覧まで暗号化されていると、libarchive は読めない（英語のエラーになる）
            if message.localizedCaseInsensitiveContains("header is encrypted") {
                return String(localized: "この書庫はファイル名の一覧まで暗号化されているため、開けません（7z・rar のパスワードには対応していません）")
            }
            return message
        }
        return String(localized: "書庫を読めませんでした")
    }
}
