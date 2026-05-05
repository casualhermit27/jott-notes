import SwiftUI

struct IOSFolderComposerView: View {
    let folderId: UUID?

    @ObservedObject private var noteStore = NoteStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var name = ""
    @State private var selectedColor: FolderColorTag = .lavender

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ds.canvas.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    header
                    nameField
                    colorPicker
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ds.inkMute)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createFolder() }
                        .fontWeight(.semibold)
                        .foregroundStyle(trimmedName.isEmpty ? ds.inkFaintest : ds.accent)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedColor.color.opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selectedColor.color.opacity(0.28), lineWidth: 1)
                    )
                Image(systemName: "folder.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selectedColor.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Folder color")
                    .font(.jottBody(14, weight: .semibold))
                    .foregroundStyle(ds.ink)
                Text("Pick a color for the new folder.")
                    .font(.jottCaption(12))
                    .foregroundStyle(ds.inkFaint)
            }

            Spacer()
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.jottCaption(12, weight: .medium))
                .foregroundStyle(ds.inkFaint)

            TextField("Folder name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .textFieldStyle(.plain)
                .font(.jottBody(15))
                .foregroundStyle(ds.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(ds.surfaceAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ds.hairline, lineWidth: 1)
                )
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color")
                .font(.jottCaption(12, weight: .medium))
                .foregroundStyle(ds.inkFaint)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 10)], spacing: 10) {
                ForEach(FolderColorTag.allCases, id: \.self) { tag in
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            selectedColor = tag
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(tag.color.opacity(selectedColor == tag ? 0.22 : 0.12))
                                    .frame(width: 54, height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(selectedColor == tag ? tag.color.opacity(0.55) : tag.color.opacity(0.20), lineWidth: selectedColor == tag ? 1.4 : 1)
                                    )
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(tag.color)
                                if selectedColor == tag {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(ds.canvas)
                                        .offset(x: 14, y: -10)
                                }
                            }
                            Text(tag.rawValue.capitalized)
                                .font(.jottCaption(11, weight: .medium))
                                .foregroundStyle(ds.inkFaint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func createFolder() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }
        _ = noteStore.createFolder(name: trimmed, colorTag: selectedColor, parentId: folderId)
        dismiss()
    }
}
