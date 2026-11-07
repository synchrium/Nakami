//
//  ArchiveWriter.swift
//  Nakami
//
//  Created by synchrium on 2026/11/01
//
//  Copyright (C) 2026  synchrium
//

import Foundation
import CArchive

/// 作る書庫の形式
nonisolated enum ArchiveFormat: String, CaseIterable, Identifiable, Sendable {
    case zip = "zip"
    case sevenZip = "7z"
    case tarGz = "tar.gz"
    case tarXz = "tar.xz"

    var id: Self { self }
    /// 拡張子（そのまま画面にも出す）
    var fileExtension: String { rawValue }
    /// パスワードと文字コードを選べるのは zip だけ（libarchive が書けるのは zip の暗号だけ。
    /// 7z と tar は名前をいつも Unicode で持つので、文字コードを選ぶ必要がない）
    var isZip: Bool { self == .zip }
}

/// zip のファイル名の文字コード
nonisolated enum WriteEncoding: String, CaseIterable, Identifiable, Sendable {
    case utf8 = "utf8"
    case shiftJIS = "shiftJIS"

    var id: Self { self }
    var label: LocalizedStringResource {
        switch self {
        case .utf8: "UTF-8"
        case .shiftJIS: "Shift_JIS"
        }
    }
    /// libarchive の zip:hdrcharset に渡す名前
    var charset: String {
        switch self {
        case .utf8: "UTF-8"
        case .shiftJIS: "CP932"
        }
    }
}

/// zip のパスワードの方式
nonisolated enum ZipEncryption: String, CaseIterable, Identifiable, Sendable {
    case aes256 = "aes256"
    case zipCrypto = "zipcrypt"

    var id: Self { self }
    var label: LocalizedStringResource {
        switch self {
        case .aes256: "AES-256（強い。Windows 標準の展開では開けない）"
        case .zipCrypto: "ZipCrypto（弱い。Windows 標準でも開ける）"
        }
    }
}

/// 書庫に入れる 1 項目。窓の中で組み立てた木を、書き出す順に平らにしたもの
nonisolated struct PlanItem: Sendable {
    enum Kind: Sendable {
        case folder
        case file(URL, size: Int64, executable: Bool)
        case symlink(String)
    }
    let path: String        // 書庫の中のパス（「資料/表.csv」）
    let kind: Kind
    let modified: Date?
}

nonisolated struct WriteOptions: Sendable {
    var format: ArchiveFormat
    var encoding: WriteEncoding     // zip だけ
    var encryption: ZipEncryption   // zip だけ
    var password: String?           // zip だけ。nil ならパスワードなし
}

nonisolated struct WriteResult: Sendable {
    var files = 0
    var warnings: [String] = []     // Shift_JIS で表せない名前など（書けたが気をつけること）
}

/// libarchive で書庫を書く
nonisolated enum ArchiveWriter {
    /// Mac が勝手に作るファイル。Windows の人に渡すと邪魔なので入れない
    static func isJunk(_ name: String) -> Bool {
        name == ".DS_Store" || name == "__MACOSX" || name.hasPrefix("._")
    }

    /// plan のとおりに url へ書庫を書く。失敗したら書きかけのファイルは消す
    static func write(_ plan: [PlanItem], to url: URL, options: WriteOptions) throws -> WriteResult {
        // 書き出し用のハンドル（読むときの archive_read_new に当たる）
        guard let a = archive_write_new() else {
            throw ArchiveError.failed(String(localized: "libarchive の初期化に失敗しました"))
        }
        defer { archive_write_free(a) }

        switch options.format {
        case .zip:
            archive_write_set_format_zip(a)
        case .sevenZip:
            archive_write_set_format_7zip(a)
        case .tarGz:
            archive_write_set_format_pax(a)
            archive_write_add_filter_gzip(a)
        case .tarXz:
            archive_write_set_format_pax(a)
            archive_write_add_filter_xz(a)
        }

        if options.format.isZip {
            // アプリは C ロケールで動くので、名前の文字コードを必ず指定する。
            // 指定しないと UTF-8 の印（フラグ）が付かず、Windows で化ける
            var settings = ["zip:hdrcharset=\(options.encoding.charset)"]
            if let password = options.password {
                settings.append("zip:encryption=\(options.encryption.rawValue)")
                archive_write_set_passphrase(a, password)
            }
            guard archive_write_set_options(a, settings.joined(separator: ",")) == ARCHIVE_OK else {
                throw ArchiveError.failed(ArchiveReader.errorString(a))
            }
        }

        guard archive_write_open_filename(a, url.path) == ARCHIVE_OK else {
            throw ArchiveError.failed(ArchiveReader.errorString(a))
        }

        do {
            var result = WriteResult()
            for item in plan {
                try writeItem(item, to: a, result: &result)
            }
            // 7z はここで一覧をまとめて書くので、閉じるところまで確かめる
            guard archive_write_close(a) == ARCHIVE_OK else {
                throw ArchiveError.failed(ArchiveReader.errorString(a))
            }
            return result
        } catch {
            archive_write_close(a)
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func writeItem(_ item: PlanItem, to a: OpaquePointer, result: inout WriteResult) throws {
        guard let entry = archive_entry_new() else { return }
        defer { archive_entry_free(entry) }

        // 名前は UTF-8 で渡す（zip で Shift_JIS を選んだときは libarchive が変換する）
        archive_entry_set_pathname_utf8(entry, item.path)
        let mtime = item.modified ?? Date()
        archive_entry_set_mtime(entry, time_t(mtime.timeIntervalSince1970), 0)

        var source: URL?
        switch item.kind {
        case .folder:
            archive_entry_set_filetype(entry, UInt32(S_IFDIR))
            archive_entry_set_perm(entry, 0o755)
        case .file(let url, let size, let executable):
            archive_entry_set_filetype(entry, UInt32(S_IFREG))
            archive_entry_set_perm(entry, executable ? 0o755 : 0o644)
            archive_entry_set_size(entry, size)
            source = url
        case .symlink(let target):
            archive_entry_set_filetype(entry, UInt32(S_IFLNK))
            archive_entry_set_perm(entry, 0o755)
            archive_entry_set_symlink_utf8(entry, target)
        }

        let r = archive_write_header(a, entry)
        if r < ARCHIVE_WARN {
            throw ArchiveError.failed("\(item.path): \(ArchiveReader.errorString(a))")
        }
        if r == ARCHIVE_WARN {
            // Shift_JIS で表せない字（絵文字など）は「?」になる。書けてはいるので、あとで知らせる
            result.warnings.append("\(item.path): \(ArchiveReader.errorString(a))")
        }

        if let source {
            try copyFile(source, to: a, path: item.path)
            result.files += 1
        }
    }

    /// ファイルの中身を少しずつ読んで書庫に書く（大きなファイルでもメモリを使い切らない）
    private static func copyFile(_ url: URL, to a: OpaquePointer, path: String) throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ArchiveError.failed(String(localized: "読めないファイルがあります: \(path)"))
        }
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            let written = chunk.withUnsafeBytes { archive_write_data(a, $0.baseAddress, chunk.count) }
            if written < 0 {
                throw ArchiveError.failed("\(path): \(ArchiveReader.errorString(a))")
            }
        }
    }
}
