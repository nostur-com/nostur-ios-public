import SwiftUI
import PhotosUI
import Vision
import NavigationBackport

@available(iOS 16.0, *)
struct ProfileScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var readingPhoto = false
    @State private var photoError = false
    @State private var completed = false
    let onScan: (String) -> Void

    var body: some View {
        NBNavigationStack {
            NWCQRScannerSheet(instruction: String(localized: "Point your camera at a Nostr profile QR code")) { value in
                finish(value)
            }
            .safeAreaInset(edge: .bottom) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(readingPhoto ? "Reading photo…" : "Scan from photo", systemImage: "photo")
                        .padding()
                }
                .disabled(readingPhoto)
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
            }
            .task(id: photo) {
                guard let photo else { return }
                readingPhoto = true
                defer { readingPhoto = false }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else {
                        photoError = true
                        return
                    }
                    let values = await Task.detached(priority: .userInitiated) {
                        let request = VNDetectBarcodesRequest()
                        request.symbologies = [.qr]
                        try? VNImageRequestHandler(data: data).perform([request])
                        return request.results?.compactMap(\.payloadStringValue) ?? []
                    }.value
                    guard !Task.isCancelled else { return }
                    guard let value = values.first(where: { ScannedProfile.parse($0) != nil }) else {
                        photoError = true
                        return
                    }
                    finish(value)
                } catch { photoError = true }
            }
            .alert("No profile found", isPresented: $photoError) {
                Button("OK", role: .cancel) { photo = nil }
            } message: {
                Text("Choose a photo containing a Nostr npub or nprofile QR code.")
            }
        }.nbUseNavigationStack(.never)
    }

    private func finish(_ value: String) {
        guard !completed else { return }
        completed = true
        onScan(value)
        dismiss()
    }
}
