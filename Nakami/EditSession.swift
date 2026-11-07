//
//  EditSession.swift
//  Nakami
//
//  Created by synchrium on 2026/11/07
//
//  Copyright (C) 2026  synchrium
//

import Foundation

/// 今ある書庫の編集。書庫を見る窓で全部を一時フォルダに取り出し、新しい書庫の窓に読み込む。
/// 保存するときは書庫を全部書き直す（libarchive には「中の 1 つだけ差し替える」機能が無い。7-Zip も中身は同じやり方）
@MainActor
final class EditSession {
    let id = UUID()
    /// 編集している書庫
    let archiveURL: URL
    /// 取り出した中身を置いた一時フォルダ
    let folder: URL
    let format: ArchiveFormat
    let encoding: WriteEncoding
    /// 元の書庫のパスワード（zip だけ）。保存するときに引き継ぐ
    let password: String?
    /// 元の zip のパスワードの方式。保存するときに引き継ぐ（ZipCrypto の zip を AES にすると、
    /// 送ってきた Windows の人が標準の機能で開けなくなるため）
    let encryption: ZipEncryption?
    /// この窓で一度保存して、元の書庫をもうゴミ箱へ入れたか
    var backedUp = false
    private let accessing: Bool

    init(archiveURL: URL, folder: URL, format: ArchiveFormat, encoding: WriteEncoding, password: String?) {
        self.archiveURL = archiveURL
        self.folder = folder
        self.format = format
        self.encoding = encoding
        self.password = password
        encryption = password == nil ? nil : (Self.zipUsesAES(archiveURL) ? .aes256 : .zipCrypto)
        // 書庫を見る窓を先に閉じても保存できるように、この編集の分の許可も持っておく（数を数える仕組みなので、見る窓の分とは別）
        accessing = archiveURL.startAccessingSecurityScopedResource()
    }

    // MARK: - 窓どうしの受け渡し

    /// 窓を開くときに渡す値（ComposeRequest）は Codable で、URL の許可は運べない。
    /// なので本体はここに置き、窓には id だけを渡す
    private static var sessions: [UUID: EditSession] = [:]

    static func register(_ session: EditSession) {
        sessions[session.id] = session
    }

    static func session(_ id: UUID) -> EditSession? {
        sessions[id]
    }

    /// 編集の窓を閉じたら、許可を返して一時フォルダを消す
    static func close(_ id: UUID) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        if session.accessing { session.archiveURL.stopAccessingSecurityScopedResource() }
        try? FileManager.default.removeItem(at: session.folder)
    }

    // MARK: - 一時フォルダ

    /// 取り出す一時フォルダの親。アプリの起動時に空にする
    nonisolated static var root: URL {
        AppTemp.root.appending(path: "Edit", directoryHint: .isDirectory)
    }

    nonisolated static func newFolder() -> URL {
        root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    // MARK: - 形式

    /// 書き直せる形式か。拡張子で決める（上書きするので、元と同じ形式でしか書かない）
    nonisolated static func format(of url: URL) -> ArchiveFormat? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".zip") { return .zip }
        if name.hasSuffix(".7z") { return .sevenZip }
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .tarGz }
        if name.hasSuffix(".tar.xz") || name.hasSuffix(".txz") { return .tarXz }
        return nil
    }

    /// zip のパスワードが AES か。zip の目次（セントラルディレクトリ）の各項目の圧縮方式が 99 なら AES
    /// （AES の zip は本当の圧縮方式を別の場所に書き、ここには 99 を書く決まり）。
    /// libarchive は方式を教えてくれないので、目次を自分で読む
    nonisolated static func zipUsesAES(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= 22 else { return false }
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }

        // 目次の終わりの印（PK\5\6）を後ろから探す（後ろにコメントが付いていることがある）
        var end = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        while end >= lowest && u32(end) != 0x0605_4B50 { end -= 1 }
        guard end >= lowest else { return false }

        // 目次の先頭から、各項目（PK\1\2）を順に見る
        var p = u32(end + 16)
        for _ in 0..<u16(end + 10) {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else { break }
            let encrypted = u16(p + 8) & 1 != 0
            if encrypted && u16(p + 10) == 99 { return true }
            p += 46 + u16(p + 28) + u16(p + 30) + u16(p + 32)
        }
        return false
    }

    // MARK: - 上書き保存

    /// 新しい書庫（一時ファイル）で元の書庫を置き換える。
    /// その窓で最初の保存なら、元の書庫はゴミ箱へ入れる（失敗しても「戻す」で戻せるように）。
    /// 2 回目からは前に保存したものをそのまま置き換える
    func replace(with newFile: URL) throws {
        let fm = FileManager.default
        if !backedUp {
            var trashed: NSURL?
            do {
                // ゴミ箱へ（Windows の SHFileOperation に FOF_ALLOWUNDO を付けたものに当たる）
                try fm.trashItem(at: archiveURL, resultingItemURL: &trashed)
            } catch {
                throw ArchiveError.failed(String(localized: "元の書庫をゴミ箱に入れられませんでした: \(error.localizedDescription)"))
            }
            do {
                try fm.copyItem(at: newFile, to: archiveURL)
            } catch {
                // 置けなかったら、ゴミ箱から元に戻す
                if let trashed = trashed as URL? {
                    try? fm.moveItem(at: trashed, to: archiveURL)
                }
                throw ArchiveError.failed(String(localized: "保存できませんでした（元の書庫は戻しました）: \(error.localizedDescription)"))
            }
            backedUp = true
        } else {
            // 前に保存したものを消して置く。replaceItemAt は同じフォルダに作業用のファイルを作ることがあり、
            // サンドボックスでは選んだファイル以外に書けないので使わない（元の書庫は 1 回目にゴミ箱へ入れてある）
            try fm.removeItem(at: archiveURL)
            try fm.copyItem(at: newFile, to: archiveURL)
        }
    }
}

extension Notification.Name {
    /// 書庫を上書き保存した。object は書庫の URL。同じ書庫を開いている見る窓が読み直す
    static let archiveDidChange = Notification.Name("NakamiArchiveDidChange")
}
