import SwiftUI

/// Create or edit a launcher row. Offers either a raw URL or a Shortcuts name
/// that is converted into a percent-encoded shortcuts:// URL.
struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss

    enum SourceKind: String, CaseIterable, Identifiable {
        case url = "網址"
        case shortcut = "捷徑"
        var id: String { rawValue }
    }

    let existingItem: LauncherItem?
    let onSave: (LauncherItem) -> Void

    @State private var kind: SourceKind
    @State private var name: String
    @State private var urlText: String
    @State private var shortcutName: String

    init(existingItem: LauncherItem?, onSave: @escaping (LauncherItem) -> Void) {
        self.existingItem = existingItem
        self.onSave = onSave
        let item = existingItem
        _kind = State(initialValue: item.map { ShortcutsURL.isShortcutURL($0.url) ? .shortcut : .url } ?? .url)
        _name = State(initialValue: item?.name ?? "")
        _urlText = State(initialValue: (item.flatMap { ShortcutsURL.isShortcutURL($0.url) ? nil : $0.url }) ?? "")
        _shortcutName = State(initialValue: item.flatMap { ShortcutsURL.shortcutName(from: $0.url) } ?? "")
    }

    private var resolvedURL: String {
        switch kind {
        case .url:
            return LauncherItem.clampURL(urlText)
        case .shortcut:
            return ShortcutsURL.runShortcut(named: shortcutName.trimmingCharacters(in: .whitespaces))
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !resolvedURL.isEmpty && URL(string: resolvedURL) != nil
    }

    var body: some View {
        Form {
            Section("顯示名稱") {
                TextField("例如：電話", text: $name)
                    .accessibilityLabel("顯示名稱")
                counter(of: name, limit: Limits.maxNameLength)
            }

            Section("開啟方式") {
                Picker("類型", selection: $kind) {
                    ForEach(SourceKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch kind {
                case .url:
                    TextField("https:// 或 scheme://", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("網址")
                    counter(of: urlText, limit: Limits.maxURLLength)
                case .shortcut:
                    TextField("在「捷徑」App 裡的名稱", text: $shortcutName)
                        .accessibilityLabel("捷徑名稱")
                    counter(of: shortcutName, limit: Limits.maxNameLength)
                    LabeledContent("產生的網址", value: resolvedURL)
                        .font(.caption)
                        .lineLimit(nil)
                    Text("iOS 無法列出你的捷徑；名稱必須與捷徑 App 中完全相同。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("儲存") {
                    onSave(LauncherItem(id: existingItem?.id ?? UUID(), name: name, url: resolvedURL))
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .navigationTitle(existingItem == nil ? "新增項目" : "編輯項目")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func counter(of text: String, limit: Int) -> some View {
        let n = text.count
        Text("\(n)/\(limit)")
            .font(.caption2)
            .foregroundStyle(n > limit ? .red : .secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("已使用 \(n) 字，上限 \(limit) 字")
    }
}
