//
//  GifSearcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/05/2023.
//

import SwiftUI
import NukeUI

struct GifSearcher: View {
    @EnvironmentObject var theme:Theme
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
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
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
                            .buttonStyle(NRButtonStyle(theme: Theme.default, style: .borderedProminent))
                        }
                    }
                }
                .frame(height: 30)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(searchResults) { gifResult in
                        VStack {
                            if let gif = gifResult.media_formats["nanogif"], let url = URL(string: gif.url) {
                                LazyImage(url: url) { state in
                                    if let container = state.imageContainer, container.type ==  .gif, let data = container.data {
                                        GIFImage(data: data)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .hCentered()
                                            .background(theme.lineColor.opacity(0.2))
                                            .onTapGesture {
                                                if let url = gifResult.media_formats["gif"]?.url {
                                                    onSelect(url)
                                                    dismiss()
                                                }
                                            }
                                    }
                                }
                                .frame(height: 90)
                            }
                        }
                    }
                    if searchResults.isEmpty {
                        ForEach(topResults) { gifResult in
                            VStack {
                                if let gif = gifResult.media_formats["nanogif"], let url = URL(string: gif.url) {
                                    LazyImage(url: url) { state in
                                        if let container = state.imageContainer, container.type ==  .gif, let data = container.data {
                                            GIFImage(data: data)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .hCentered()
                                                .background(theme.lineColor.opacity(0.2))
                                                .onTapGesture {
                                                    if let url = gifResult.media_formats["gif"]?.url {
                                                        onSelect(url)
                                                        dismiss()
                                                    }
                                                }
                                        }
                                    }
                                    .frame(height: 90)
                                }
                            }
                        }
                    }
//                    ForEach(tags) { tag in
//                        Text(tag.name)
//                    }
                }
            }
            Spacer()
            .onChange(of: searchTerm) { newValue in
                search(newValue)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .padding()
        .onAppear {
            initial()
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

#Preview("Tenor") {
    NavigationStack {
        GifSearcher { gifURL in
            print("Gif selected: \(gifURL)")
        }
    }
    .environmentObject(Theme.default)
}
