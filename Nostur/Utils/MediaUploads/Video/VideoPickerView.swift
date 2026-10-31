import SwiftUI

/// Use the same Photos import for ordinary and short videos. The picker requests
/// the current representation; Nostur owns the final conversion and privacy check.
struct VideoPickerView: View {
    @Binding var selectedVideoURL: URL?
    @Binding var isLoading: Bool
    @Binding var importError: String?

    var body: some View {
        VineVideoPicker(selectedVideoURL: $selectedVideoURL, isLoading: $isLoading, importError: $importError)
    }
}

func compressVideoAsync(inputURL: URL, outputURL: URL) async -> URL? {
    do {
        let prepared = try await VideoPreparation.prepare(inputURL: inputURL)
        try FileManager.default.moveItem(at: prepared.url, to: outputURL)
        return outputURL
    } catch { return nil }
}
