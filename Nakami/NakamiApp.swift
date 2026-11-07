//
//  NakamiApp.swift
//  Nakami
//  
//  Created by synchrium on 2026/10/31
//  
//  Copyright (C) 2026  synchrium
//

import AppKit
import SwiftUI

@main
struct NakamiApp: App {
    // SwiftUI だけでは書けない、アプリ全体の動きを AppKit の delegate で決める
    // （WPF の Application.ShutdownMode に当たるもの）
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 書庫を見る窓。Finder でダブルクリックされた書庫（onOpenURL）もここで開く
        WindowGroup(id: "viewer") {
            ContentView()
        }
        .commands {
            AboutCommands()
            FileCommands()
            HelpCommands()
        }

        // 新しい書庫を作る窓（⌘N）。Finder から来た書庫をここで開かないよう、外からの「開け」は受けない
        WindowGroup("新しい書庫", id: "compose", for: ComposeRequest.self) { $request in
            ComposeView(initialURLs: request?.urls ?? [], editID: request?.editID)
        }
        .handlesExternalEvents(matching: [])

        // 早見表の窓。WindowGroup と違い 1 つだけ開く（もう開いていれば前に出る）
        Window("キー操作の早見表", id: "shortcuts") {
            ShortcutsView()
        }

        // 設定の窓。これを書くだけで、メニューに「設定…」（⌘,）ができる
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 前に新しい書庫の窓から Finder へドラッグしたときのコピーの残りを消す
        try? FileManager.default.removeItem(at: ComposeDragItem.root)
        // 編集のために取り出した中身の残りも消す
        try? FileManager.default.removeItem(at: EditSession.root)
        // Finder の右クリックの「サービス」の受け口（Nakami-Info.plist の NSServices に書いたもの）
        NSApp.servicesProvider = ComposeService()

        // アプリに来るキー入力を先に見る（WinForms の KeyPreview = true に近い）。
        // 窓の中に操作の対象（フォーカス）が無くても Esc を受け取れる
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            Self.closeWindowOnEscape(event) ? nil : event
        }
    }

    /// 設定でオンなら、Esc で今の窓を閉じる。閉じたら true（そのキーはここで使い切る）
    private static func closeWindowOnEscape(_ event: NSEvent) -> Bool {
        let escape: UInt16 = 53
        guard event.keyCode == escape,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              UserDefaults.standard.bool(forKey: SettingsKey.escClosesWindow),
              let window = NSApp.keyWindow,
              NSApp.modalWindow == nil,             // 「開く」などのダイアログが出ていない
              window.attachedSheet == nil,          // シート（窓に付くダイアログ）が出ていない
              !(window.firstResponder is NSText),   // 文字を打つ欄にいない（そこでの Esc は文字を消す）
              !(window.identifier?.rawValue.contains("Settings") ?? false),  // 設定の窓は閉じない
              !String(describing: type(of: window)).contains("QLPreviewPanel")  // Quick Look の窓は自分で Esc を扱う
        else { return false }
        window.performClose(nil)
        return true
    }

    /// 最後の窓を閉じたときにアプリを終わるか。設定（⌘,）で決める。既定は Mac のふつうの動き（終わらない）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.quitWhenLastWindowClosed)
    }
}

/// メニューの「ファイル」の「新規」。⌘N は新しい書庫を作る窓、書庫を見る窓は ⌥⌘N
struct FileCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // メニューは窓が無くても起動時に作られるので、ここで窓を開く機能を預ける
        // （Finder の右クリックから頼まれて裏で起動したときは、窓が 1 つも開かない）
        let _ = ComposeOpener.remember(openWindow)
        CommandGroup(replacing: .newItem) {
            Button("新しい書庫を作る") { openWindow(id: "compose") }
                .keyboardShortcut("n", modifiers: .command)
            Button("新しい窓（書庫を見る）") { openWindow(id: "viewer") }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
    }
}

/// メニューの「Nakami について」。macOS の標準の窓に、ライセンスと libarchive の著作権表示を足して出す
/// （libarchive の BSD ライセンスは、配るときに著作権表示を見せることを求めている。全文は THIRD_PARTY_NOTICES.md と同じ）
struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Nakami について") {
                NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
            }
        }
    }

    /// 窓の下の欄に出す文。色は labelColor（ダークモードでは白）にする。
    /// Credits.rtf を置く方法だと色が黒のままになり、ダークモードで読めなくなりやすい
    private static var credits: NSAttributedString {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: center,
        ]
        let small: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: """
            Released under the MIT License.
            https://github.com/synchrium/Nakami

            This app uses libarchive (BSD 2-Clause License).
            https://www.libarchive.org/


            """, attributes: body))
        text.append(NSAttributedString(string: """
            libarchive
            Copyright (c) 2003-2018 Tim Kientzle and the libarchive contributors
            Copyright (c) 2016 Martin Matuska
            All rights reserved.

            Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
            1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer in this position and unchanged.
            2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

            THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
            """, attributes: small))
        return text
    }
}

/// メニューの「ヘルプ」。Xcode が用意する「Nakami ヘルプ」（中身が無い）を早見表に置き換える
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("キー操作の早見表") { openWindow(id: "shortcuts") }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

/// SwiftUI の「窓を開く」機能を預かっておく。AppDelegate（サービス）からは直接呼べないので、
/// 窓が表示されたときに預かり、まだ無ければ頼まれたものを取っておいて、預かったときに開く
@MainActor
enum ComposeOpener {
    private static var openWindow: OpenWindowAction?
    private static var pending: [[URL]] = []

    /// 預かる。取っておいた頼みがあれば開き、そのときは true。
    /// メニューを作っている最中にも呼ばれるので、窓を開くのは少しあと（次の回）にする
    @discardableResult
    static func remember(_ action: OpenWindowAction) -> Bool {
        openWindow = action
        let waiting = pending
        pending = []
        if !waiting.isEmpty {
            DispatchQueue.main.async {
                for urls in waiting { open(urls) }
            }
        }
        return !waiting.isEmpty
    }

    static func open(_ urls: [URL]) {
        guard let openWindow else {
            pending.append(urls)
            return
        }
        openWindow(id: "compose", value: ComposeRequest(urls: urls))
        // 前に出られれば出る（ほかのアプリが前にいると断られることがある。
        // そのときも窓は ComposeView が orderFrontRegardless で手前に出す）
        NSApp.activate()
    }
}

/// Finder の右クリック →「サービス」→「Nakami で圧縮」の受け口。
/// 選んだファイルが貼り付けボード（クリップボードの仲間）で届く。
/// メソッドの名前は Info.plist の NSMessage と同じにする（Objective-C のセレクターで呼ばれる）
final class ComposeService: NSObject {
    @objc func composeFiles(_ pboard: NSPasteboard, userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self],
                                      options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = String(localized: "ファイルを受け取れませんでした") as NSString
            return
        }
        ComposeOpener.open(urls)
    }
}
