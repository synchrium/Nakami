//
//  DirectoryListing.swift
//  Nakami
//
//  Created by synchrium on 2026/10/31
//
//  Copyright (C) 2026  synchrium
//

import Foundation

/// 一覧の 1 行（今いるフォルダの中の、ファイルかフォルダ）
nonisolated struct ListItem: Identifiable, Sendable {
    let name: String
    var isDirectory: Bool
    var size: Int64 = 0             // フォルダなら中身の合計
    var modified: Date?
    var entryIDs: Set<Int> = []     // この行に含まれる書庫の項目（フォルダなら中身全部）
    var hasOwnEntry = false         // 書庫にこの行そのものの項目があるか（無いフォルダもある）
    var containsEncrypted = false   // パスワード付きのもの（フォルダなら中身に）があるか

    var id: String { name }
}

/// 書庫の項目の一覧から、あるフォルダの中身を作る。
/// zip にはフォルダの項目を持たないもの（「ディズニー/写真.jpg」だけで「ディズニー/」が無い）もあるので、
/// ファイルのパスからフォルダを組み立てる
nonisolated enum DirectoryListing {
    /// directory は "" （いちばん上）か "資料/" のように「/」で終わる
    static func items(in directory: String, entries: [ArchiveEntry], encoding: NameEncoding) -> [ListItem] {
        var map: [String: ListItem] = [:]
        for e in entries {
            let path = e.safePath(encoding)
            guard path.hasPrefix(directory) else { continue }
            let rest = path.dropFirst(directory.count)
            guard !rest.isEmpty else { continue }

            // rest が「写真.jpg」ならこの階層のファイル、「サブ/写真.jpg」ならこの階層の「サブ」フォルダの中身
            let parts = rest.split(separator: "/", maxSplits: 1)
            let name = String(parts[0])
            let isSelf = parts.count == 1
            var item = map[name] ?? ListItem(name: name, isDirectory: false)
            item.isDirectory = item.isDirectory || !isSelf || e.isDirectory
            item.entryIDs.insert(e.id)
            item.containsEncrypted = item.containsEncrypted || e.isEncrypted
            if !e.isDirectory { item.size += e.size }
            if isSelf {
                item.modified = e.modified
                item.hasOwnEntry = true
            } else if !item.hasOwnEntry, let m = e.modified, m > (item.modified ?? .distantPast) {
                // フォルダの項目が無ければ、中身のいちばん新しい日時を出す
                item.modified = m
            }
            map[name] = item
        }
        // フォルダが先、あとは名前順（Finder と同じ並べ方。「写真 2」が「写真 10」より前）
        return map.values.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
