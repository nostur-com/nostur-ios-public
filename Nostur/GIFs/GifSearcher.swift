//
//  GifSearcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/05/2023.
//

import SwiftUI
import NukeUI

struct MasonryLayout<Item: Identifiable, Content: View>: View {
    let columns: Int
    let spacing: CGFloat
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    
    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { columnIndex in
                LazyVStack(spacing: spacing) {
                    let columnItems = items.enumerated()
                        .filter { $0.offset % columns == columnIndex }
                        .map(\.element)
                    ForEach(columnItems) { item in
                        content(item)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

@MainActor
private final class GifSearchModel: ObservableObject {
    @Published private(set) var searchResults: [TenorResult] = []
    @Published private(set) var topResults: [TenorResult] = []
    @Published private(set) var autocompleteResults: [String] = []
    @Published private(set) var suggestionResults: [String] = []
    @Published private(set) var activeSearchTerm = ""
    @Published private(set) var scrollUpdater = UUID()

    private var searchTask: Task<Void, Never>?
    private var featuredTask: Task<Void, Never>?

    var gifItems: [TenorResult] {
        activeSearchTerm.isEmpty ? topResults : searchResults
    }

    var bothResults: [String] {
        autocompleteResults + suggestionResults.filter { !autocompleteResults.contains($0) }
    }

    func loadFeatured() {
        featuredTask?.cancel()
        featuredTask = Task { [weak self] in
            guard let url = gifAPIURL(
                path: "featured",
                queryItems: [URLQueryItem(name: "limit", value: "10")]
            ) else { return }

            let response: TenorResponse? = await Self.fetch(URLRequest(url: url))
            guard !Task.isCancelled, let self, let results = response?.results else { return }
            self.topResults = results
        }
    }

    func search(_ rawSearchTerm: String) {
        searchTask?.cancel()

        let searchTerm = rawSearchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        activeSearchTerm = searchTerm

        guard !searchTerm.isEmpty else {
            searchResults = []
            autocompleteResults = []
            suggestionResults = []
            return
        }

        searchTask = Task { [weak self] in
            guard let searchURL = gifAPIURL(
                path: "search",
                queryItems: [
                    URLQueryItem(name: "q", value: searchTerm),
                    URLQueryItem(name: "limit", value: "30"),
                    URLQueryItem(name: "media_filter", value: "gif,nanogif")
                ]
            ), let autocompleteURL = gifAPIURL(
                path: "autocomplete",
                queryItems: [
                    URLQueryItem(name: "q", value: searchTerm),
                    URLQueryItem(name: "limit", value: "5")
                ]
            ), let suggestionsURL = gifAPIURL(
                path: "search_suggestions",
                queryItems: [
                    URLQueryItem(name: "q", value: searchTerm),
                    URLQueryItem(name: "limit", value: "10")
                ]
            ) else { return }

            async let searchResponse: TenorResponse? = Self.fetch(URLRequest(url: searchURL))
            async let autocompleteResponse: AutoCompleteResponse? = Self.fetch(URLRequest(url: autocompleteURL))
            async let suggestionsResponse: AutoCompleteResponse? = Self.fetch(URLRequest(url: suggestionsURL))
            let responses = await (searchResponse, autocompleteResponse, suggestionsResponse)

            guard !Task.isCancelled, let self, self.activeSearchTerm == searchTerm else { return }
            self.searchResults = responses.0?.results ?? []
            self.autocompleteResults = responses.1?.results ?? []
            self.suggestionResults = responses.2?.results ?? []
            self.scrollUpdater = UUID()
        }
    }

    func cancel() {
        searchTask?.cancel()
        featuredTask?.cancel()
    }

    private nonisolated static func fetch<T: Decodable>(_ request: URLRequest) async -> T? {
        do {
            return try await makeWebRequest(urlRequest: request)
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            L.og.error("GIF API error: \(error)")
            return nil
        }
    }
}

struct GifSearcher: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var searchTerm = ""
    @StateObject private var searchModel = GifSearchModel()
    @AppStorage("use_blossom_for_gifs") private var useBlossom = false
    
    var onSelect: (String) -> ()
    
    @State private var blossomViewState: ViewState = .none
    
    enum BlossomError: Error {
        case noServers
        case invalidServerURL
    }
    
    enum ViewState: Equatable {
        case none
        case uploadingGif
        case uploadFailed
    }
    
    var body: some View {
        VStack {
            SearchBox(prompt: String(localized:"Search GIF", comment:"Placeholder in GIF search field"), text: $searchTerm)
                .containerShape(.rect(cornerRadius: 8.0))
                .padding(1)
                .background(theme.lineColor)
                .containerShape(.rect(cornerRadius: 8.0))
            
            if account() != nil, SettingsStore.shared.defaultMediaUploadService.name == BLOSSOM_LABEL {
                Toggle(isOn: $useBlossom) {
                    Text("Post GIF using Blossom")
                }
            }
            
            if !searchModel.autocompleteResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack {
                        ForEach(searchModel.bothResults, id: \.self) { result in
                            Button(result) {
                                searchTerm = result
//                                autocompleteResults = []
//                                suggestionResults = []
                            }
                            .buttonStyle(NRButtonStyle(style: .borderedProminent))
                        }
                    }
                }
                .frame(height: 30)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    MasonryLayout(
                        columns: 3,
                        spacing: 5,
                        items: searchModel.gifItems
                    ) { gifResult in
                        gifItemView(gifResult: gifResult)
                    }
                    .id("top")
                }
                .onChange(of: searchTerm) { newValue in
                    searchModel.search(newValue)
                }
                .onChange(of: searchModel.scrollUpdater) { _ in
                    withAnimation {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
        .disabled(blossomViewState == ViewState.uploadingGif)
        .overlay {
            if blossomViewState == ViewState.uploadingGif {
                ZStack {
                    theme.listBackground.opacity(0.95)
                    
                    VStack {
                        Text("Uploading to Blossom server(s)...")
                        ProgressView()
                        ProgressView(value: 0.5, total: 1.0)
                    }
                }
            }
        }
        
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { dismiss() }
            }
            
           
        }
        .modifier { // need to hide glass bg in 26+
            if #available(iOS 26.0, *) {
                $0.toolbar {
                    // if date is after june 29 2026
                    if Date.now.timeIntervalSince1970 > 1782597600 {
                        ToolbarItem(placement: .topBarTrailing) {
                            Image("PoweredByKlipy")
                                .resizable()
                                .foregroundColor(.gray)
                                .scaledToFit()
                                .frame(height: 20.0)
//                                .padding(.top, 16)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                    else {
                        ToolbarItem(placement: .topBarTrailing) {
                            Image("PoweredByTenor")
                                .resizable()
                                .foregroundColor(.gray)
                                .scaledToFit()
                                .frame(height: 10.0)
                                .padding(.top, 16)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                }
            }
            else {
                $0.toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        // if date is after june 29 2026
                        if Date.now.timeIntervalSince1970 > 1782597600 {
                            Image("PoweredByKlipy")
                                .resizable()
                                .foregroundColor(.gray)
                                .scaledToFit()
                                .frame(height: 20.0)
//                                .padding(.top, 16)
                        }
                        else {
                            Image("PoweredByTenor")
                                .resizable()
                                .foregroundColor(.gray)
                                .scaledToFit()
                                .frame(height: 10.0)
                                .padding(.top, 16)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .onAppear {
            searchModel.loadFeatured()
        }
        .onDisappear {
            searchModel.cancel()
        }
    }
    
    @MainActor
    private func uploadToBlossom(_ url: String) async throws {
        guard let account = account() else { return }
        
        guard !SettingsStore.shared.blossomServerList.isEmpty else {
            throw BlossomError.noServers
        }
            
        // download gif from url
        guard let gifUrl = URL(string: url) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await ImageProcessing.shared.content.data(
            for: ImageRequest(url: gifUrl)
        )
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let contentType = httpResponse.mimeType ?? "image/gif"
        let blossomFile = BlossomUploadFile(data: data, contentType: contentType)
        
        // sign auth header
        let authHeader = try await getBlossomAuthHeader(account: account, blossomFile: blossomFile)
        
        guard let firstServer = SettingsStore.shared.blossomServerList.first, let firstServerUrl = URL(string: firstServer) else {
            throw BlossomError.invalidServerURL
        }
        
        // upload to blossom server
        let blossomGifUrl = try await blossomUpload(authHeader: authHeader, blossomFile: blossomFile, contentType: contentType, blossomServer: firstServerUrl)
        let sha256 = blossomFile.sha256
#if DEBUG
        L.og.debug("GIF uploaded: \(blossomGifUrl), SHA256: \(sha256)")
#endif
        onSelect(blossomGifUrl)
        dismiss()
        
        // upload to blossom mirrors
        if SettingsStore.shared.blossomServerList.count > 1 {
            Task {
                for server in SettingsStore.shared.blossomServerList.dropFirst(1) {
                    guard let mirrorServer = URL(string: server) else { continue }
                    
                    let mirrorUrl = try await blossomMirror(authHeader: authHeader, url: blossomGifUrl, hash: sha256, contentType: contentType, blossomServer: mirrorServer)
#if DEBUG
                    L.og.debug("GIF mirrored: \(mirrorUrl)")
#endif
                }
            }
        }
    }
    
    @ViewBuilder
    private func gifItemView(gifResult: TenorResult) -> some View {
        if let gif = gifResult.media_formats["nanogif"], let url = URL(string: gif.url) {
            let aspectRatio = gif.dims.count >= 2 ? CGFloat(gif.dims[0]) / CGFloat(gif.dims[1]) : 1.0
            LazyImage(url: url) { state in
                if let container = state.imageContainer,
                   container.type == .gif,
                   let data = container.data,
                   ProfileImageSafety.isSafeAnimatedImage(data, policy: .post) {
                    GIFImage(data: data, isPlaying: .constant(true))
                        .aspectRatio(aspectRatio, contentMode: .fit)
                        .background(theme.lineColor.opacity(0.2))
                        .cornerRadius(4)
                        .onTapGesture {
                            if let gifUrl = gifResult.media_formats["gif"]?.url {
                                if useBlossom {
                                    blossomViewState = .uploadingGif
                                    Task {
                                        do {
                                            try await uploadToBlossom(gifUrl)
                                        }
                                        catch {
                                            Task { @MainActor in
                                                blossomViewState = .uploadFailed
                                            }
                                        }
                                    }
                                }
                                else {
                                    onSelect(gifUrl)
                                    dismiss()
                                }
                            }
                        }
                }
            }
            .id(gifResult.id)
        }
    }
    
}

import NavigationBackport

#Preview("Tenor") {
    NBNavigationStack {
        GifSearcher { gifURL in
            print("Gif selected: \(gifURL)")
        }
    }
    .environmentObject(Themes.default)
}
