//
//  PasswordSheet.swift
//  Nakami
//
//  Created by synchrium on 2026/11/01
//
//  Copyright (C) 2026  synchrium
//

import SwiftUI
import Carbon

/// パスワードを打つ間だけ、入力を英字に切り替える。
/// SecureField でも日本語入力はオンのままで、変換中の文字が画面に出るのに欄には入らず紛らわしい。
/// TIS（Text Input Sources）は入力ソースを扱う API で、Windows の ImmSetOpenStatus で IME を閉じるのに近い
@MainActor
final class RomanInputSwitcher {
    /// 切り替える前の入力ソース（戻すときに使う）
    private var saved: TISInputSource?

    func switchToRoman() {
        guard saved == nil else { return }
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let roman = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue()
        else { return }
        saved = current
        TISSelectInputSource(roman)
    }

    func restore() {
        guard let saved else { return }
        TISSelectInputSource(saved)
        self.saved = nil
    }
}

/// パスワードを聞くシート（窓の上から下りてくる窓。WPF の ShowDialog で出すダイアログに当たる）。
/// 開いたらすぐ入力欄に打てる。Return で OK、Esc でキャンセル。違っていたら閉じずにその場で知らせる
struct PasswordSheet: View {
    let archiveName: String
    /// 合っているか確かめる。合っていれば true（呼ぶ側がシートを閉じる）
    let check: (String) -> Bool
    let cancel: () -> Void

    @State private var input = ""
    @State private var wrong = false
    @FocusState private var fieldFocused: Bool
    @State private var inputSwitcher = RomanInputSwitcher()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("パスワード", systemImage: "lock.fill")
                .font(.headline)
            Text("「\(archiveName)」にはパスワードが付いています")
                .fixedSize(horizontal: false, vertical: true)
            // SecureField は文字を●で隠す入力欄（WPF の PasswordBox に当たる）
            SecureField("パスワード", text: $input)
                .focused($fieldFocused)
                .onSubmit(submit)
            if wrong {
                Text("パスワードが違います。もう一度入れてください")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                // .cancelAction は Esc、.defaultAction は Return（WPF の IsCancel・IsDefault に当たる）
                Button("キャンセル", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK", action: submit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        // 開いたらすぐ入力欄に打てるようにする
        .defaultFocus($fieldFocused, true)
        .onAppear { fieldFocused = true }
        // 欄にカーソルがある間だけ英字に。離れたら・閉じたら元の入力に戻す
        .onChange(of: fieldFocused, initial: true) { _, focused in
            if focused { inputSwitcher.switchToRoman() } else { inputSwitcher.restore() }
        }
        .onDisappear { inputSwitcher.restore() }
    }

    private func submit() {
        if !check(input) {
            wrong = true
            input = ""
            fieldFocused = true
        }
    }
}
