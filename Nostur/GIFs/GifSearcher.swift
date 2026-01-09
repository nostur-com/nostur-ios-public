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
        GeometryReader { geometry in
            let totalSpacing = spacing * CGFloat(columns - 1)
            let columnWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)
            
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0..<columns, id: \.self) { columnIndex in
                    LazyVStack(spacing: spacing) {
                        ForEach(0..<content.count, id: \.self) { itemIndex in
                            if itemIndex % columns == columnIndex {
                                content[itemIndex]
                                    .frame(width: columnWidth)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct GifSearcher: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) var dismiss
    @State var searchTerm = ""
    @State var searchResults:[TenorResult] = []
    @State var topResults:[TenorResult] = []
    @State var tags:[TenorCategory] = []
    @State var autocompleteResults:[String] = []
    @State var _suggestionResults:[String] = []
    var bothResults:[String] {
        (autocompleteResults + (_suggestionResults.filter { !autocompleteResults.contains($0) }))
    }
    var onSelect:(String) -> ()
    
    private var gifItems: [TenorResult] {
        searchResults.isEmpty ? topResults : searchResults
    }
    
    var body: some View {
        VStack {
            SearchBox(prompt: String(localized:"Search GIF", comment:"Placeholder in GIF search field"), text: $searchTerm)
            HStack {
                Spacer()
                Image("PoweredByTenor")
                    .resizable()
                    .foregroundColor(.gray)
                    .scaledToFit()
                    .frame(height: 10.0)
                    .padding(.bottom, 10)
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { dismiss() }
            }
        }
        .padding()
        .onAppear {
            initial()
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
                                onSelect(gifUrl)
                                dismiss()
                            }
                        }
                }
            }
        }
    }
    
    func search(_ searchTerm:String) {
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
