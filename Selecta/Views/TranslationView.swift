// Modified for Selecta: Swift port and reduced feature set, 2026-11-02.
// Swift port of Easydict's Mini query layout, colors and result headers (GPL-3.0).
// Copyright © 2022–2026 izual and contributors.
import SwiftUI

struct TranslationView: View {
    @ObservedObject var model: TranslationModel
    @ObservedObject var preferences: Preferences
    var onSettings: () -> Void
    var onSearch: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var mainBackground: Color { scheme == .dark ? Color(red: 35/255, green: 35/255, blue: 37/255) : .white }
    private var queryBackground: Color { scheme == .dark ? Color(red: 48/255, green: 49/255, blue: 50/255) : Color(white: 244/255) }
    private var barBackground: Color { scheme == .dark ? Color(red: 44/255, green: 45/255, blue: 46/255) : Color(white: 241/255) }
    private var resultBackground: Color { scheme == .dark ? queryBackground : Color(white: 246/255) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { model.pinned.toggle() } label: { Image(systemName: model.pinned ? "pin.fill" : "pin") }.help("固定窗口")
                WindowDragArea().frame(maxWidth: .infinity, maxHeight: .infinity).help("拖动窗口")
                Button(action: onSettings) { Image(systemName: "gearshape") }.help("设置 ⌘,").accessibilityLabel("设置")
                Button(action: onSearch) { Image(systemName: "magnifyingglass") }
                    .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("用 Google 搜索原文").accessibilityLabel("Google 搜索原文")
            }.font(.system(size: 14)).foregroundStyle(.secondary)
                .buttonStyle(.borderless).padding(.horizontal, 10).frame(height: 28)
            ScrollView {
                VStack(spacing: 7) {
                    VStack(spacing: 0) {
                        QueryEditor(text: $model.input) { model.translate() }.frame(height: PopupLayout.inputHeight(model.input, width: model.popupWidth - 20))
                        HStack(spacing: 10) {
                            if model.source == .auto && model.detected != .auto {
                                Text(model.detected.name).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            if model.ocrBusy {
                                ProgressView().controlSize(.mini)
                                Text("本地识别中…").font(.caption2)
                                Button("取消") { model.cancelOCR() }
                            }
                            Spacer(minLength: 0)
                            Button { model.input = "" } label: { Image(systemName: "xmark.circle") }.help("清空")
                            Button { model.translate() } label: { Image(systemName: "arrow.turn.down.left") }
                                .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("翻译，回车")
                        }.font(.system(size: 12)).foregroundStyle(.secondary).buttonStyle(.borderless)
                            .padding(.horizontal, 10).frame(height: 24)
                    }.background(queryBackground, in: RoundedRectangle(cornerRadius: 8))
                    HStack(spacing: 0) {
                        languageMenu(source: true).frame(maxWidth: .infinity)
                        Button { model.swap() } label: { Image(systemName: "arrow.left.arrow.right") }
                            .buttonStyle(.borderless).frame(width: 26).help("交换语言")
                        languageMenu(source: false).frame(maxWidth: .infinity)
                    }.font(.system(size: 12)).frame(height: 35)
                        .background(barBackground, in: RoundedRectangle(cornerRadius: 8))
                    if let notice = model.notice {
                        Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(5)
                    }
                    ForEach(preferences.enabledProviders.filter { model.results[$0] != nil }) { provider in
                        if let state = model.results[provider] { resultCard(provider, state: state) }
                    }
                }.padding(.horizontal, 10).padding(.bottom, 7)
            }
        }.background(mainBackground).frame(minWidth: 360, minHeight: 155)
            .ignoresSafeArea()
            .onChange(of: model.source) { _ in if !model.input.isEmpty { model.translate() } }
            .onChange(of: model.target) { _ in if !model.input.isEmpty { model.translate() } }
    }
    private func languageMenu(source: Bool) -> some View {
        let current = source ? model.source : model.target
        return Menu {
            ForEach(Language.allCases) { language in
                Button(language == .auto && !source ? "自动选择" : language.name) {
                    if source { model.source = language } else { model.target = language }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current == .auto && !source ? "自动选择" : current.name)
                Image(systemName: "chevron.down").font(.system(size: 8))
            }.frame(maxWidth: .infinity)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden)
    }
    private func resultCard(_ provider: TranslationProvider, state: TranslationState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    if model.collapsedProviders.contains(provider) { model.collapsedProviders.remove(provider) }
                    else { model.collapsedProviders.insert(provider) }
                } label: {
                    HStack(spacing: 6) {
                        Image(provider.rawValue).resizable().scaledToFit().frame(width: 16, height: 16)
                        Text(provider.rawValue).font(.system(size: 12))
                        Image(systemName: model.collapsedProviders.contains(provider) ? "chevron.right" : "chevron.down").font(.system(size: 8))
                    }
                }.buttonStyle(.plain)
                Spacer()
                if case .loading = state { ProgressView().controlSize(.mini) }
                if case .success(let text) = state {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("复制译文")
                }
            }.foregroundStyle(.secondary).padding(.horizontal, 8).frame(height: 28).background(barBackground)
            if !model.collapsedProviders.contains(provider) {
                Group {
                    switch state {
                    case .loading: Text("翻译中…").foregroundStyle(.secondary)
                    case .success(let text): Text(text).textSelection(.enabled)
                    case .failure(let message): Text(message).foregroundStyle(.red).textSelection(.enabled)
                    }
                }.font(.system(size: 14)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
        }.background(resultBackground).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
