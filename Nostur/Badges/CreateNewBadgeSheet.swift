//
//  CreateNewBadgeSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI
import NavigationBackport
import NukeUI

struct CreateNewBadgeSheet: View {
    
    @Environment(\.theme) private var theme
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.dismiss) private var dismiss
    
    @State private var badgeCode = ""
    @State private var name = ""
    @State private var description = ""
    @State private var image1024 = ""
    @State private var image256 = ""
    @State private var errorMessage: String?
    
    private enum FocusedField {
        case badgeCode
    }
    
    @FocusState private var focusedField: FocusedField?
    
    private var trimmedCode: String { badgeCode.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func validOptionalURL(_ value: String) -> Bool {
        guard !value.isEmpty else { return true }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    private var isValid: Bool {
        !trimmedCode.isEmpty
            && !trimmedName.isEmpty
            && !trimmedDescription.isEmpty
            && validOptionalURL(image1024)
            && validOptionalURL(image256)
    }
    
    var body: some View {
        Form {
            Section("Badge details") {
                TextField(String(localized:"Code (bravery, verified_human, early_adoptor)", comment:"Label for input field for badge code on Badge creation screen"), text: $badgeCode)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .lineLimit(1)
                    .focused($focusedField, equals: .badgeCode)
                TextField(String(localized:"Name", comment:"Label for input field for badge name on Badge creation screen"), text: $name)
                    .lineLimit(1)
                TextField(String(localized:"Description", comment:"Label for input field for badge description on Badge creation screen"), text: $description)
                    .lineLimit(2)
            }
            .listRowBackground(theme.background)

            Section("Artwork") {
                TextField(String(localized:"Image URL (1024x1024)", comment:"Label for input field for badge image on Badge creation screen"), text: $image1024)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .lineLimit(1)
                TextField(String(localized:"Thumbnail URL (256x256)", comment:"Label for input field for badge image on Badge creation screen"), text: $image256)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .lineLimit(1)
                if !validOptionalURL(image1024) || !validOptionalURL(image256) {
                    Text("Enter a valid HTTP or HTTPS image URL.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let previewURL = URL(string: image256.isEmpty ? image1024 : image256),
                   !image256.isEmpty || !image1024.isEmpty {
                    LazyImage(url: previewURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else if state.isLoading {
                            ProgressView()
                        } else {
                            Label("Image could not be loaded", systemImage: "exclamationmark.triangle")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                }
            }
            .listRowBackground(theme.background)
        }
        .scrollContentBackgroundHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") {
                    createBadge()
                }
                .buttonStyleGlassProminent()
                .disabled(!isValid)
            }
        }
        .navigationTitle(String(localized:"Create new badge", comment:"Navigation title for Badge creation screen"))
        .onAppear { focusedField = .badgeCode }
        .alert("Could not create badge", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    func createBadge() {
        guard isValid else { return }
        let newBadge = createBadgeDefinition(
            trimmedCode,
            name: trimmedName,
            description: trimmedDescription,
            image1024: image1024,
            thumb256: image256
        )
        
        do {    
            let newBadgeSigned = try la.account.signEvent(newBadge)
            let bgContext = bg()
            bgContext.perform {
                _ = Event.saveEvent(event: newBadgeSigned, context: bgContext)
                DataProvider.shared().saveToDiskNow(.bgContext)
            }
            Unpublisher.shared.publishNow(newBadgeSigned)
            dismiss()
        }
        catch {
            L.og.error("🔴🔴 could not create badge \(error)")
            errorMessage = error.localizedDescription
        }
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
