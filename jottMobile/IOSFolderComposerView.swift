import SwiftUI

struct IOSFolderComposerView: View {
    let folderId: UUID?

    @ObservedObject private var noteStore = NoteStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var name = ""
    @State private var selectedColor: FolderColorTag = .lavender
    @FocusState private var nameFocused: Bool

    private var ds: JottDS { JottDS(isDark: scheme == .dark) }
    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            // Title
            Text("New Folder")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ds.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            // Name field — minimal underline style
            VStack(spacing: 0) {
                TextField("Folder name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(ds.ink)
                    .focused($nameFocused)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)

                Rectangle()
                    .fill(nameFocused ? selectedColor.color : ds.hairline)
                    .frame(height: nameFocused ? 1.5 : 0.5)
                    .padding(.horizontal, 24)
                    .animation(.easeInOut(duration: 0.18), value: nameFocused)
            }

            Spacer().frame(height: 32)

            // Folder icon color row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(FolderColorTag.allCases, id: \.self) { tag in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                selectedColor = tag
                            }
                        } label: {
                            ZStack {
                                // Selection ring
                                Circle()
                                    .fill(tag.color.opacity(selectedColor == tag ? 0.14 : 0))
                                    .frame(width: 52, height: 52)

                                Image(systemName: "folder.fill")
                                    .font(.system(
                                        size: selectedColor == tag ? 28 : 24,
                                        weight: .regular
                                    ))
                                    .foregroundStyle(tag.color.opacity(selectedColor == tag ? 1.0 : 0.50))
                                    .scaleEffect(selectedColor == tag ? 1.0 : 0.92)
                            }
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selectedColor)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer().frame(height: 32)

            // Create button
            Button {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                _ = noteStore.createFolder(name: trimmed, colorTag: selectedColor, parentId: folderId)
                dismiss()
            } label: {
                Text("Create Folder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canCreate ? .white : ds.inkFaintest)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        canCreate ? selectedColor.color : ds.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .animation(.easeInOut(duration: 0.18), value: canCreate)
                    .animation(.easeInOut(duration: 0.18), value: selectedColor)
            }
            .disabled(!canCreate)
            .padding(.horizontal, 24)

            Spacer().frame(height: 12)
        }
        .background(ds.canvas.ignoresSafeArea())
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(24)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                nameFocused = true
            }
        }
    }
}
