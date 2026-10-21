import SwiftUI
import PhotosUI

/// Einstieg für alle Import-Wege. Zeigt den laufenden Import und öffnet den Review als Sheet.
struct ImportHubView: View {
    @Environment(ImportCoordinator.self) private var coordinator
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showLinkSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.l) {
                    privacyBanner
                    importOptions
                    if case .working(let message) = coordinator.phase {
                        workingCard(message)
                    }
                    if case .failed(let message) = coordinator.phase {
                        errorCard(message)
                    }
                }
                .padding(AppTheme.Spacing.l)
            }
            .background(AppTheme.background)
            .navigationTitle("Importieren")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let image = await item.loadUIImage() {
                    await coordinator.importImage(image, source: .screenshot)
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                Task { await coordinator.importImage(image, source: .photo) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLinkSheet) {
            InstagramLinkSheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: Binding(
            get: { if case .review = coordinator.phase { return true } else { return false } },
            set: { if !$0 { coordinator.reset() } }
        )) {
            if case .review(let draft) = coordinator.phase {
                ImportReviewView(draft: draft)
                    .interactiveDismissDisabled()
            }
        }
    }

    // MARK: - Bausteine

    private var privacyBanner: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.trust)
            VStack(alignment: .leading, spacing: 2) {
                Text("100 % auf deinem Gerät")
                    .font(.headline)
                Text("Texterkennung und Speicherung laufen offline. Nichts wird hochgeladen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.trust.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }

    private var importOptions: some View {
        VStack(spacing: AppTheme.Spacing.m) {
            PhotosPicker(selection: $photoItem, matching: .any(of: [.images, .screenshots])) {
                ImportOptionLabel(
                    title: "Screenshot oder Foto",
                    subtitle: "Aus der Mediathek wählen – Text wird per Apple Vision erkannt",
                    systemImage: "photo.on.rectangle.angled"
                )
            }
            .buttonStyle(.plain)

            if CameraPicker.isAvailable {
                Button { showCamera = true } label: {
                    ImportOptionLabel(title: "Kochbuch abfotografieren", subtitle: "Seite oder Zettel direkt mit der Kamera erfassen", systemImage: "camera")
                }
                .buttonStyle(.plain)
            }

            Button { showLinkSheet = true } label: {
                ImportOptionLabel(title: "Instagram-Link", subtitle: "Beitrag oder Reel einfügen, Caption wird ausgelesen", systemImage: "link")
            }
            .buttonStyle(.plain)

            Button {
                if let text = UIPasteboard.general.string, !text.isEmpty {
                    coordinator.importText(text, source: ImportSource(kind: .shared, url: nil))
                } else {
                    coordinator.startManualEntry()
                }
            } label: {
                ImportOptionLabel(title: "Text einfügen oder manuell anlegen", subtitle: "Zwischenablage wird erkannt, sonst leeres Rezept", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.plain)
        }
    }

    private func workingCard(_ message: String) -> some View {
        HStack(spacing: AppTheme.Spacing.m) {
            ProgressView()
            Text(message).font(.subheadline)
        }
        .padding(AppTheme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.warning)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                Text(message).font(.subheadline)
                Button("Verstanden") { coordinator.dismissError() }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(AppTheme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

private struct ImportOptionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(AppTheme.label)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(AppTheme.Spacing.l)
        .frame(minHeight: 72)
        .cardBackground()
        .contentShape(Rectangle())
    }
}

/// Eingabe eines Instagram-Links mit Zwischenablage-Vorschlag.
private struct InstagramLinkSheet: View {
    @Environment(ImportCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var pasteFailed = false
    @FocusState private var focused: Bool

    private var isValid: Bool { InstagramLinkParser.parse(text: input) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://www.instagram.com/p/…", text: $input)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit(start)
                } footer: {
                    Text("Die Beitragsseite wird direkt von instagram.com geladen – ohne Zwischenserver. Klappt das nicht (z. B. Login-Wand), kannst du den Text einfügen oder einen Screenshot importieren.")
                }

                if UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings {
                    Section {
                        Button {
                            // Lesezugriff erst auf Nutzeraktion – zeigt den System-Hinweis nur einmal und bewusst.
                            if let clipboard = UIPasteboard.general.string, InstagramLinkParser.parse(text: clipboard) != nil {
                                input = clipboard
                            } else {
                                pasteFailed = true
                            }
                        } label: {
                            Label("Link aus Zwischenablage einfügen", systemImage: "doc.on.clipboard")
                        }
                    } footer: {
                        if pasteFailed { Text("In der Zwischenablage ist kein Instagram-Link.") }
                    }
                }
            }
            .navigationTitle("Instagram-Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren", action: start).disabled(!isValid)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func start() {
        guard isValid else { return }
        let link = input
        dismiss()
        Task { await coordinator.importInstagramLink(link) }
    }
}

#Preview {
    ImportHubView()
        .environment(ImportCoordinator.preview)
        .modelContainer(RecipeSchemaV1.previewContainer())
}
