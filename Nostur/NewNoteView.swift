//
//  NewNoteView.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import SwiftUI

class Autcompleter {
    var usernames = ["Amstelveen", "Amsterdam", "Amsterdam-Zuidoost", "Amstetten"]
    var suggestions = [String]()
    
    func lookup(prefix: String) -> [String] {
        let lowercasedPrefix = prefix.lowercased()
        return usernames.filter { $0.lowercased().hasPrefix(lowercasedPrefix) }
    }
    func autocomplete(_ text: String) {
        guard !text.isEmpty else {
            suggestions = []
            return
        }
        let newSuggestions = lookup(prefix: text)
        
        if isSuggestion(in: suggestions, equalTo: text) {
            // Do not offer only one suggestion same as the input
            suggestions = []
        } else {
            suggestions = newSuggestions
        }
    }
    
    private func isSuggestion(in suggestions: [String], equalTo text: String) -> Bool {
        guard let suggestion = suggestions.first, suggestions.count == 1 else {
            return false
        }
        
        return suggestion.lowercased() == text.lowercased()
    }
}

struct NewNoteView: View {
    
    var autocompleter = Autcompleter()
    @State var input: String = ""
 
    var body: some View {
        VStack {
            VStack {
                TextField("", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .onChange(of: input) { newValue in
                        autocompleter.autocomplete(input)
                    }
            }
            List(autocompleter.suggestions, id: \.self) { suggestion in
                ZStack {
                    Text(suggestion)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

struct NewNoteView_Previews: PreviewProvider {
    static var previews: some View {
        NewNoteView()
    }
}
