//
//  CreateNewBadgeSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI
import NavigationBackport
import PhotosUI
import UniformTypeIdentifiers
import NostrEssentials

struct CreateNewBadgeSheet: View {

    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.dismiss) private var dismiss

    private let originalDefinition: NEvent?

    @State private var badgeCode = ""
    @State private var name = ""
    @State private var badgeDescription = ""
    @State private var selectedArtwork: UIImage?
    @State private var isImportingArtwork = false
    @State private var artworkError: String?
    @State private var errorMessage: String?
    @State private var creationStatus: String?
    @State private var isCreating = false
    @State private var showAdvanced = false
    @State private var identifierWasEdited = false
    @State private var existingDefinitionName: String?
    @State private var showReplaceConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var showPublishingInfo = false
    @State private var removesExistingArtwork = false

    init(badge: Event? = nil) {
        let definition = badge?.toNEvent()
        originalDefinition = definition
        _badgeCode = State(initialValue: definition?.badgeCode?.value ?? "")
        _name = State(initialValue: definition?.badgeName?.value ?? "")
        _badgeDescription = State(initialValue: definition?.badgeDescription?.value ?? "")
        _identifierWasEdited = State(initialValue: definition != nil)
        _existingDefinitionName = State(initialValue: definition?.badgeName?.value)
    }

    private enum FocusedField {
        case name
        case description
        case badgeCode
    }

    @FocusState private var focusedField: FocusedField?

    private var trimmedCode: String { badgeCode.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { badgeDescription.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isEditing: Bool { originalDefinition != nil }

    private var originalImageURL: String {
        originalDefinition?.badgeImage?.tag[safe: 1] ?? ""
    }

    private var originalThumbnailURL: String {
        originalDefinition?.badgeThumb?.tag[safe: 1] ?? ""
    }

    private var hasArtwork: Bool {
        selectedArtwork != nil || (!removesExistingArtwork && (!originalImageURL.isEmpty || !originalThumbnailURL.isEmpty))
    }

    private var hasChanges: Bool {
        if let originalDefinition {
            return trimmedCode != (originalDefinition.badgeCode?.value ?? "")
                || trimmedName != (originalDefinition.badgeName?.value ?? "")
                || trimmedDescription != (originalDefinition.badgeDescription?.value ?? "")
                || selectedArtwork != nil
                || removesExistingArtwork
        }
        return !trimmedCode.isEmpty || !trimmedName.isEmpty || !trimmedDescription.isEmpty || selectedArtwork != nil
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && !trimmedDescription.isEmpty && !trimmedCode.isEmpty
    }

    private var createButtonTitle: String {
        isEditing || existingDefinitionName != nil ? String(localized: "Update badge") : String(localized: "Create badge")
    }

    var body: some View {
        NXForm {
            formSections
        }
        .navigationTitle(isEditing ? String(localized: "Edit badge") : String(localized: "New badge"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancel() }
                    .disabled(isCreating)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(createButtonTitle) { submit() }
                    .buttonStyleGlassProminent()
                    .disabled(isCreating || !isValid || (isEditing && !hasChanges))
            }
        }
        .interactiveDismissDisabled(hasChanges || isCreating)
        .onAppear {
            if !isEditing { focusedField = .name }
        }
        .onChange(of: name) { newValue in
            guard !identifierWasEdited else { return }
            badgeCode = badgeIdentifier(from: newValue)
        }
        .task(id: trimmedCode) {
            if !isEditing { await updateExistingDefinition() }
        }
        .fileImporter(
            isPresented: $isImportingArtwork,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            loadImportedArtwork(result)
        }
        .confirmationDialog(
            "Discard this badge?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Your badge details and selected artwork will be lost.")
        }
        .alert("About badge publishing", isPresented: $showPublishingInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your badge definition will be signed by your current account and published publicly to Nostr.")
        }
        .alert("Update existing badge?", isPresented: $showReplaceConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Update badge", role: .destructive) {
                Task { await createBadge() }
            }
        } message: {
            Text("The identifier “\(trimmedCode)” already exists. Publishing will replace its name, description, and artwork.")
        }
        .alert(isEditing ? "Could not update badge" : "Could not create badge", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var formSections: some View {
        artworkSection
        badgeDetailsSection
        advancedSection

        Section {
            Button("About badge publishing", systemImage: "info.circle") {
                showPublishingInfo = true
            }
        }

        if let creationStatus {
            Section {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(creationStatus)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var artworkSection: some View {
        Section {
            artworkPicker

            if let artworkError {
                Label {
                    Text(artworkError)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        } header: {
            Text("Artwork")
        } footer: {
            Text("Nostur crops the image to a square and creates the required sizes automatically.")
        }
    }

    private var badgeDetailsSection: some View {
        Section("Details") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Name", text: $name, prompt: Text("Community Builder"))
                    .textContentType(.name)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .name)
                    .onSubmit { focusedField = .description }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if #available(iOS 16.0, *) {
                    TextField(
                        "Description",
                        text: $badgeDescription,
                        prompt: Text("What did someone do to earn this badge?"),
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .description)
                    .onSubmit { focusedField = nil }
                } else {
                    TextField(
                        "Description",
                        text: $badgeDescription,
                        prompt: Text("What did someone do to earn this badge?")
                    )
                    .submitLabel(.done)
                    .focused($focusedField, equals: .description)
                    .onSubmit { focusedField = nil }
                }
            }
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                TextField("Badge identifier", text: identifierBinding, prompt: Text("community_builder"))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .badgeCode)
                    .onSubmit { focusedField = nil }
                    .disabled(isEditing)

                Text(isEditing
                     ? "The identifier cannot be changed because it is the permanent address of this badge."
                     : "This becomes part of the badge’s permanent Nostr address. Changing it creates a different badge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !isEditing, let existingDefinitionName {
                    Label(
                        "This identifier is already used by “\(existingDefinitionName)”. Creating will update that badge.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private var artworkPicker: some View {
        HStack(spacing: 14) {
            artworkPreview(size: 88)

            VStack(alignment: .leading, spacing: 8) {
                if #available(iOS 16.0, *) {
                    BadgePhotosPickerButton(
                        hasArtwork: hasArtwork,
                        onImage: { image in
                            selectedArtwork = image
                            removesExistingArtwork = false
                            artworkError = nil
                        },
                        onError: { error in
                            artworkError = error.localizedDescription
                        }
                    )
                }

                Button {
                    isImportingArtwork = true
                } label: {
                    Label("Choose file", systemImage: "folder")
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
                .accessibilityLabel("Choose from Files")

                if hasArtwork {
                    Button(role: .destructive) {
                        selectedArtwork = nil
                        removesExistingArtwork = true
                        artworkError = nil
                    } label: {
                        Label("Remove artwork", systemImage: "trash")
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func artworkPreview(size: CGFloat) -> some View {
        Group {
            if let selectedArtwork {
                Image(uiImage: selectedArtwork)
                    .resizable()
                    .scaledToFill()
            } else {
                if let originalDefinition, !removesExistingArtwork,
                   badgeArtworkURL(for: originalDefinition, targetWidth: Int(size)) != nil {
                    BadgeArtwork(nBadge: originalDefinition, size: size)
                } else {
                    artworkPlaceholder
                }
            }
        }
        .frame(width: size, height: size)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2))
        }
        .clipped()
    }

    private var artworkPlaceholder: some View {
        Image(systemName: "seal")
            .font(.system(size: 38, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var identifierBinding: Binding<String> {
        Binding(
            get: { badgeCode },
            set: { newValue in
                identifierWasEdited = true
                badgeCode = badgeIdentifier(from: newValue)
            }
        )
    }

    private func submit() {
        focusedField = nil
        guard isValid else { return }

        if isEditing {
            Task { await createBadge() }
        } else if existingDefinitionName != nil {
            showReplaceConfirmation = true
        } else {
            Task { await createBadge() }
        }
    }

    private func cancel() {
        focusedField = nil
        if hasChanges {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func loadImportedArtwork(_ result: Result<[URL], Error>) {
        artworkError = nil
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data) else {
                throw BadgeCreationError.couldNotReadArtwork
            }
            selectedArtwork = image
            removesExistingArtwork = false
        } catch {
            artworkError = error.localizedDescription
        }
    }

    @MainActor
    private func updateExistingDefinition() async {
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
        } catch {
            return
        }
        guard !trimmedCode.isEmpty else {
            existingDefinitionName = nil
            return
        }

        let request = Event.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "kind == %d AND pubkey == %@ AND dTag == %@",
            BadgeKinds.definition,
            la.account.publicKey,
            trimmedCode
        )
        if let existingDefinition = try? context().fetch(request).first {
            existingDefinitionName = existingDefinition.toNEvent().badgeName?.value ?? trimmedCode
        } else {
            existingDefinitionName = nil
        }
    }

    @MainActor
    private func createBadge() async {
        guard isValid, !isCreating else { return }
        isCreating = true
        errorMessage = nil

        do {
            var fullSizeURL = removesExistingArtwork ? "" : originalImageURL
            var thumbnailURL = removesExistingArtwork ? "" : originalThumbnailURL

            if let selectedArtwork {
                creationStatus = String(localized: "Preparing artwork…")
                let artwork = try badgeArtworkData(from: selectedArtwork)

                creationStatus = String(localized: "Uploading artwork…")
                fullSizeURL = try await uploadBadgeArtwork(
                    artwork.fullSize,
                    filename: "badge-1024.jpg",
                    account: la.account
                )
                thumbnailURL = try await uploadBadgeArtwork(
                    artwork.thumbnail,
                    filename: "badge-256.jpg",
                    account: la.account
                )
            }

            creationStatus = String(localized: "Publishing badge…")
            let badge = createBadgeDefinition(
                trimmedCode,
                name: trimmedName,
                description: trimmedDescription,
                image1024: fullSizeURL,
                thumb256: thumbnailURL
            )
            let signedBadge = try la.account.signEvent(badge)
            let bgContext = bg()
            await bgContext.perform {
                _ = Event.saveEvent(event: signedBadge, context: bgContext)
                DataProvider.shared().saveToDiskNow(.bgContext)
            }
            Unpublisher.shared.publishNow(signedBadge)
            dismiss()
        } catch {
            L.og.error("🔴🔴 could not create badge \(error)")
            errorMessage = error.localizedDescription
            isCreating = false
            creationStatus = nil
        }
    }
}

@available(iOS 16.0, *)
private struct BadgePhotosPickerButton: View {
    let hasArtwork: Bool
    let onImage: (UIImage) -> Void
    let onError: (Error) -> Void

    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
            Label(hasArtwork ? "Change photo" : "Choose photo", systemImage: "photo.on.rectangle.angled")
                .font(.subheadline)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(hasArtwork ? "Change photo" : "Choose from Photos")
        .onChange(of: selectedPhoto) { item in
            guard let item else { return }
            Task { await loadArtwork(from: item) }
        }
    }

    @MainActor
    private func loadArtwork(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw BadgeCreationError.couldNotReadArtwork
            }
            onImage(image)
        } catch {
            onError(error)
        }
    }
}

private struct BadgeArtworkData {
    let fullSize: Data
    let thumbnail: Data
}

private enum BadgeCreationError: LocalizedError {
    case couldNotReadArtwork
    case couldNotPrepareArtwork
    case mediaServiceNotConfigured
    case invalidMediaResponse
    case mediaProcessingTimedOut
    case couldNotAuthorizeUpload

    var errorDescription: String? {
        switch self {
        case .couldNotReadArtwork:
            return String(localized: "The selected image could not be read.")
        case .couldNotPrepareArtwork:
            return String(localized: "The selected image could not be prepared.")
        case .mediaServiceNotConfigured:
            return String(localized: "Configure a media upload service in Settings before uploading badge artwork.")
        case .invalidMediaResponse:
            return String(localized: "The media service did not return a usable image URL.")
        case .mediaProcessingTimedOut:
            return String(localized: "The media service took too long to process the artwork.")
        case .couldNotAuthorizeUpload:
            return String(localized: "The artwork upload could not be authorized.")
        }
    }
}

private func badgeIdentifier(from value: String) -> String {
    let folded = value
        .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        .lowercased()
    let pieces = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
    return pieces.filter { !$0.isEmpty }.joined(separator: "_")
}

@MainActor
private func badgeArtworkData(from image: UIImage) throws -> BadgeArtworkData {
    guard let fullSizeImage = scaleImageToFill(image: image, height: 1024, width: 1024),
          let thumbnailImage = scaleImageToFill(image: image, height: 256, width: 256),
          let fullSizeData = fullSizeImage.jpegData(compressionQuality: 0.9),
          let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.85) else {
        throw BadgeCreationError.couldNotPrepareArtwork
    }
    return BadgeArtworkData(fullSize: fullSizeData, thumbnail: thumbnailData)
}

@MainActor
private func uploadBadgeArtwork(_ data: Data, filename: String, account: CloudAccount) async throws -> String {
    if SettingsStore.shared.defaultMediaUploadService.name == BLOSSOM_LABEL {
        guard let server = SettingsStore.shared.blossomServerList.first,
              let serverURL = URL(string: server) else {
            throw BadgeCreationError.mediaServiceNotConfigured
        }
        let file = BlossomUploadFile(data: data, contentType: "image/jpeg")
        let authorization = try await getBlossomAuthHeader(account: account, blossomFile: file)
        return try await blossomUpload(
            authHeader: authorization,
            blossomFile: file,
            contentType: "image/jpeg",
            blossomServer: serverURL
        )
    }

    guard let apiURL = badgeNip96URL() else {
        throw BadgeCreationError.mediaServiceNotConfigured
    }

    let boundary = UUID().uuidString
    let bag = MediaRequestBag(
        apiUrl: apiURL,
        uploadtype: "media",
        filename: filename,
        mediaData: data,
        authorizationHeader: "",
        boundary: boundary
    )
    let unsignedAuthorization = getUnsignedAuthorizationHeaderEvent96(
        pubkey: account.publicKey,
        sha256hex: bag.sha256hex,
        method: "POST",
        apiUrl: apiURL
    )
    let signedAuthorization = try account.signEvent(unsignedAuthorization)
    guard let authorizationHeader = toHttpAuthHeader(signedAuthorization) else {
        throw BadgeCreationError.couldNotAuthorizeUpload
    }

    var request = URLRequest(url: apiURL)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
    request.httpBody = bag.httpBody

    let (responseData, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200..<300).contains(httpResponse.statusCode) else {
        throw BadgeCreationError.invalidMediaResponse
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    var uploadResponse = try decoder.decode(UploadResponse.self, from: responseData)

    if uploadResponse.status == "processing", let processingURLString = uploadResponse.processingUrl,
       let processingURL = URL(string: processingURLString) {
        for _ in 0..<24 {
            try await Task.sleep(nanoseconds: 2_500_000_000)
            let (statusData, statusResponse) = try await URLSession.shared.data(from: processingURL)
            guard let statusHTTPResponse = statusResponse as? HTTPURLResponse,
                  (200..<300).contains(statusHTTPResponse.statusCode) else { continue }
            uploadResponse = try decoder.decode(UploadResponse.self, from: statusData)
            if uploadResponse.status != "processing" { break }
        }
    }

    guard uploadResponse.status == "success" || uploadResponse.status == "completed" else {
        if uploadResponse.status == "processing" { throw BadgeCreationError.mediaProcessingTimedOut }
        throw BadgeCreationError.invalidMediaResponse
    }
    guard let url = uploadResponse.nip94Event.tags.first(where: { $0.type == "url" })?.value,
          URL(string: url) != nil else {
        throw BadgeCreationError.invalidMediaResponse
    }
    return url
}

private func badgeNip96URL() -> URL? {
    let configured = UserDefaults.standard.string(forKey: "nip96_api_url") ?? ""
    if !configured.isEmpty { return URL(string: configured) }
    switch SettingsStore.shared.defaultMediaUploadService.name {
    case "nostrcheck.me":
        return URL(string: "https://nostrcheck.me/api/v2/media")
    case "nostr.build":
        return URL(string: "https://nostr.build/api/v2/nip96/upload")
    default:
        return nil
    }
}

struct CreateNewBadgeSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadBadges() }) {
            NBNavigationStack {
                CreateNewBadgeSheet()
            }
        }
    }
}
