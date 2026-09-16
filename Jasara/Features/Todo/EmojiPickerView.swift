import SwiftUI

/// A searchable emoji grid plus the pastel swatches. The colour is saved by name,
/// so the same task reads correctly in light and dark mode.
struct EmojiPickerView: View {
    @Binding var emoji: String
    @Binding var palette: Palette
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = Array(repeating: GridItem(.adaptive(minimum: 46), spacing: 8), count: 1)

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    EmojiBubble(emoji: emoji, palette: palette, size: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Icon").font(Face.rowStrong)
                        Text("Pick an emoji and a colour").font(Face.caption).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, Metric.gutter)

                HStack(spacing: 8) {
                    ForEach(Palette.allCases) { option in
                        Button {
                            palette = option
                        } label: {
                            Circle()
                                .fill(option.fill)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(option.ink,
                                                               lineWidth: palette == option ? 2.5 : 0))
                                .frame(width: Metric.minTarget, height: Metric.minTarget)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.label)
                        .accessibilityAddTraits(palette == option ? [.isButton, .isSelected] : .isButton)
                    }
                }

                ScrollView {
                    if query.isEmpty {
                        ForEach(EmojiCatalog.groups) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.name)
                                    .font(Face.caption.weight(.bold))
                                    .foregroundStyle(Ink.muted)
                                    .padding(.horizontal, Metric.gutter)
                                grid(group.emoji)
                            }
                            .padding(.bottom, 10)
                        }
                    } else {
                        grid(EmojiCatalog.search(query))
                    }
                }
            }
            .padding(.top, 10)
            .background(Ink.background)
            .searchable(text: $query, prompt: "Search icons")
            .navigationTitle("Task icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func grid(_ options: [String]) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    emoji = option
                } label: {
                    Text(option)
                        .font(.system(size: 26))
                        .frame(width: 46, height: 46)
                        .background(emoji == option ? palette.fill : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option)
            }
        }
        .padding(.horizontal, Metric.gutter)
    }
}
