//
//  PreviewProvider.swift
//  NakamiQuickLook
//
//  Created by synchrium on 2026/11/01
//
//  Copyright (C) 2026  synchrium
//

import Foundation
import Quartz
import UniformTypeIdentifiers

/// Finder でスペースキーを押したときのプレビュー（Quick Look）。書庫の中身の一覧を HTML にして返す。
/// Windows のプレビュー ハンドラー（IPreviewHandler）に当たるが、Finder の中ではなく別のプロセスで動く。
/// 書庫を読む部分は Nakami 本体の ArchiveReader.swift をそのまま使う
class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    /// 一覧に出す行の上限（とても大きな書庫でもすぐ出るように）
    private let maxRows = 2000

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let html = makeHTML(for: url)
        // データ方式：HTML を返すと、macOS がそれを表示してくれる
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 720, height: 560)) { reply in
            reply.stringEncoding = .utf8
            reply.title = url.lastPathComponent
            return Data(html.utf8)
        }
    }

    private func makeHTML(for url: URL) -> String {
        let listing: ArchiveListing
        do {
            listing = try ArchiveReader.list(url)
        } catch {
            return page(title: url.lastPathComponent, summary: "", body: "<p class=\"error\">\(escape(error.localizedDescription))</p>")
        }

        // フォルダの項目が無い書庫もあるので、ファイルのパスからフォルダを足して、パスの順に並べる
        var rows: [(path: String, isDirectory: Bool, size: Int64, modified: Date?, encrypted: Bool)] = []
        var folders = Set<String>()
        for e in listing.entries {
            let path = e.safePath(.auto)
            guard !path.isEmpty else { continue }
            let parts = path.split(separator: "/")
            for i in 1..<parts.count {
                folders.insert(parts[..<i].joined(separator: "/"))
            }
            if e.isDirectory {
                folders.insert(path)
            } else {
                rows.append((path, false, e.size, e.modified, e.isEncrypted))
            }
        }
        rows += folders.map { ($0, true, 0, nil, false) }
        rows.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        let files = rows.filter { !$0.isDirectory }
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        let summary = String(localized: "\(files.count) 個のファイル・\(folders.count) 個のフォルダ・\(total.formatted(.byteCount(style: .file)))")

        var html = "<table><thead><tr><th>" + escape(String(localized: "名前")) + "</th><th class=\"size\">"
            + escape(String(localized: "サイズ")) + "</th><th class=\"date\">" + escape(String(localized: "更新日時"))
            + "</th></tr></thead><tbody>"
        for row in rows.prefix(maxRows) {
            let depth = row.path.split(separator: "/").count - 1
            let name = String(row.path.split(separator: "/").last ?? "")
            let icon = row.isDirectory ? "📁" : (row.encrypted ? "🔒" : "📄")
            html += "<tr><td style=\"padding-left:\(8 + depth * 18)px\">\(icon) \(escape(name))</td>"
            html += "<td class=\"size\">\(row.isDirectory ? "" : row.size.formatted(.byteCount(style: .file)))</td>"
            html += "<td class=\"date\">\(row.modified?.formatted(date: .numeric, time: .shortened) ?? "")</td></tr>"
        }
        html += "</tbody></table>"
        if rows.count > maxRows {
            html += "<p class=\"more\">" + escape(String(localized: "ほか \(rows.count - maxRows) 件（Nakami で開くと全部見られます）")) + "</p>"
        }
        return page(title: url.lastPathComponent, summary: summary, body: html)
    }

    /// HTML の枠。ダークモードでも読めるよう、色は CSS の prefers-color-scheme で切り替える
    private func page(title: String, summary: String, body: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        :root { color-scheme: light dark; }
        body { font: 13px -apple-system, sans-serif; margin: 0; padding: 16px 20px; }
        h1 { font-size: 17px; margin: 0 0 2px; }
        .summary { color: #888; margin-bottom: 12px; }
        table { border-collapse: collapse; width: 100%; }
        th { text-align: left; font-weight: 600; color: #888; border-bottom: 1px solid rgba(128,128,128,.3); padding: 4px 8px; }
        td { padding: 3px 8px; white-space: nowrap; }
        tbody tr:nth-child(even) { background: rgba(128,128,128,.08); }
        .size, .date { text-align: right; color: #888; font-variant-numeric: tabular-nums; }
        .error, .more { color: #888; }
        </style></head><body>
        <h1>\(escape(title))</h1><div class="summary">\(escape(summary))</div>
        \(body)
        </body></html>
        """
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
