//
//  GifSearcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/05/2023.
//

import SwiftUI
import NukeUI

struct MasonryLayout<Content: View>: View {
    let columns: Int
    let spacing: CGFloat
    let content: [Content]
    
    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { columnIndex in
                LazyVStack(spacing: spacing) {
                    ForEach(0..<content.count, id: \.self) { itemIndex in
                        if itemIndex % columns == columnIndex {
                            content[itemIndex]
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct GifSearcher: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var searchTerm = ""
    @State private var searchResults: [TenorResult] = []
    @State private var topResults: [TenorResult] = []
    @State private var tags: [TenorCategory] = []
    @State private var autocompleteResults: [String] = []
    @State private var _suggestionResults: [String] = []
    @AppStorage("use_blossom_for_gifs") private var useBlossom = false
    
    var bothResults: [String] {
        (autocompleteResults + (_suggestionResults.filter { !autocompleteResults.contains($0) }))
    }
    
    var onSelect: (String) -> ()
    
    private var gifItems: [TenorResult] {
        searchResults.isEmpty ? topResults : searchResults
    }
    
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
            
            if let account = account(), SettingsStore.shared.defaultMediaUploadService.name == BLOSSOM_LABEL {
                Toggle(isOn: $useBlossom) {
                    Text("Post GIF using Blossom")
                }
            }
            
            if !autocompleteResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack {
                        ForEach(bothResults.indices, id:\.self) { index in
                            Button(bothResults[safe: index] ?? "") {
                                searchTerm = bothResults[safe: index] ?? ""
//                                autocompleteResults = []
//                                suggestionResults = []
                            }
                            .buttonStyle(NRButtonStyle(style: .borderedProminent))
                        }
                    }
                }
                .frame(height: 30)
            }
            ScrollView {
                MasonryLayout(
                    columns: 3,
                    spacing: 5,
                    content: gifItems.map { gifResult in
                        AnyView(
                            gifItemView(gifResult: gifResult)
                        )
                    }
                )
            }
            .onChange(of: searchTerm) { newValue in
                search(newValue)
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
            else {
                $0.toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .onAppear {
            initial()
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
        
        let (data, response) = try await URLSession.shared.data(from: gifUrl)
        
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
                if let container = state.imageContainer, container.type == .gif, let data = container.data {
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
        }
    }
    
    func search(_ searchTerm: String) {
        guard let searchTerm = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return }
        
        // Define the results upper limit
        let limit = 30
        
        // make initial search request for the first 8 items
        if let url = URL(string: String(format: "https://tenor.googleapis.com/v2/search?q=%@&key=%@&client_key=%@&limit=%d&media_filter=gif,nanogif",
                                        searchTerm,
                                        apikey,
                                        clientkey,
                                        limit)) {
            let searchRequest = URLRequest(url: url)
            makeWebRequest(urlRequest: searchRequest, callback: self.tenorSearchHandler)
        }
        
        
        // Get up to 5 results from the autocomplete suggestions - using the default locale of en_US
        if let url = URL(string: String(format: "https://tenor.googleapis.com/v2/autocomplete?key=%@&client_key=%@&q=%@&limit=%d",
                                        apikey,
                                        clientkey,
                                        searchTerm,
                                        5)) {
            let autoRequest = URLRequest(url: url)
            makeWebRequest(urlRequest: autoRequest, callback: tenorAutoCompleteResultsHandler)
        }
        
        if let url = URL(string: String(format: "https://tenor.googleapis.com/v2/search_suggestions?key=%@&client_key=%@&q=%@&limit=%d",
                                        apikey,
                                        clientkey,
                                        searchTerm,
                                        10)) {
            // Get the top 10 search suggestions - using the default locale of en_US
            let suggestRequest = URLRequest(url: url)
            makeWebRequest(urlRequest: suggestRequest, callback: tenorSuggestionResultsHandler)
        }
    }
    
    func initial() {
        searchTerm = ""
        searchResults = []
        topResults = []
        tags = []
        autocompleteResults = []
        _suggestionResults = []
        
        // Get the top 10 featured GIFs (updated throughout the day) - using the default locale of en_US
        if let url = URL(string: String(format: "https://tenor.googleapis.com/v2/featured?key=%@&client_key=%@&limit=%d",
                                        apikey,
                                        clientkey,
                                        10)) {
            let featuredRequest = URLRequest(url: url)
            
            makeWebRequest(urlRequest: featuredRequest, callback: tenorFeaturedResultsHandler)
        }


//           // Get the current list of categories - using the default locale of en_US
//           let categoryRequest = URLRequest(url: URL(string: String(format: "https://tenor.googleapis.com/v2/categories?key=%@&client_key=%@&limit=%d",
//                                                                    apikey, clientkey, 10))!)
//           makeWebRequest(urlRequest: categoryRequest, callback: tenorCategoryResultsHandler)

    }
    
    func tenorSearchHandler(response: TenorResponse)
    {
        if let results = response.results {
            self.searchResults = results
        }
    }
    
    func tenorCategoryResultsHandler(response: TenorResponse)
    {
        if let tags = response.tags {
            self.tags = tags
        }
    }
    
    func tenorFeaturedResultsHandler(response: TenorResponse)
    {
        if let results = response.results {
            self.topResults = results
        }
    }
    
    func tenorAutoCompleteResultsHandler(response: AutoCompleteResponse)
    {
        if let results = response.results {
            self.autocompleteResults = results
        }
    }
    
    func tenorSuggestionResultsHandler(response: AutoCompleteResponse)
    {
        if let results = response.results {
            self._suggestionResults = results
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
