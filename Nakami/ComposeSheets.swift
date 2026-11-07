//
//  ComposeSheets.swift
//  Nakami
//
//  Created by synchrium on 2026/11/01
//
//  Copyright (C) 2026  synchrium
//

import SwiftUI

/// 名前を変えるシート。Return で決定、Esc でやめる。使えない名前なら閉じずに知らせる
struct RenameSheet: View {
    let original: String
    /// 使えない名前なら理由を返す。使えれば nil
    let validate: (String) -> String?
    let commit: (String) -> Void
    let cancel: () -> Void

    @State private var name = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("名前を変える")
                .font(.headline)
            TextField("名前", text: $name)
                .focused($focused)
                .onSubmit(submit)
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("キャンセル", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK", action: submit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            name = original
            focused = true
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let reason = validate(trimmed) {
            problem = reason
        } else {
            commit(trimmed)
        }
    }
}

/// 新しい書庫のパスワードを決めるシート。打ち間違いを防ぐため 2 回入れてもらう
struct NewPasswordSheet: View {
    let commit: (String) -> Void
    let cancel: () -> Void

    @State private var first = ""
    @State private var second = ""
    @State private var inputSwitcher = RomanInputSwitcher()
    @FocusState private var focus: Field?

    private enum Field { case first, second }

    private var mismatch: Bool { !second.isEmpty && first != second }
    private var canCommit: Bool { !first.isEmpty && first == second }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("パスワードを決める", systemImage: "lock.fill")
                .font(.headline)
            Text("書庫を開く人に伝えるパスワードです。忘れると取り出せません")
                .fixedSize(horizontal: false, vertical: true)
            SecureField("パスワード", text: $first)
                .focused($focus, equals: .first)
                .onSubmit { focus = .second }
            SecureField("もう一度", text: $second)
                .focused($focus, equals: .second)
                .onSubmit { if canCommit { commit(first) } }
            if mismatch {
                Text("2 つが合っていません")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("キャンセル", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK") { commit(first) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCommit)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { focus = .first }
        // パスワードを打つ間は英字に（PasswordSheet と同じ）
        .onChange(of: focus, initial: true) { _, field in
            if field != nil { inputSwitcher.switchToRoman() } else { inputSwitcher.restore() }
        }
        .onDisappear { inputSwitcher.restore() }
    }
}
