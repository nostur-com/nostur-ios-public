//
//  SearchBox.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/05/2023.
//

import SwiftUI

struct SearchBox: View {
    
    @StateObject var debounceObject = DebounceObject()
    var prompt:LocalizedStringKey
    @Binding var text:String
    
    var body: some View {
        TextField(text: $debounceObject.text, prompt: Text(prompt).foregroundColor(Color.secondary), label: {
            Text(prompt)
        })
        .padding(5)
        .padding(.leading, 25)
        .background {
            Color("ListBackground").opacity(0.5)
                .overlay(alignment:.leading) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color.secondary)
                        .padding(.leading, 5)
                }
        }
        .overlay(alignment:.trailing) {
            if debounceObject.text != "" {
                Image(systemName: "multiply.circle.fill")
                    .foregroundColor(Color.secondary)
                    .padding(.trailing, 5)
                    .onTapGesture {
                        debounceObject.text = ""
                    }
            }
        }
        .cornerRadius(8.0)
        .onChange(of: debounceObject.debouncedText) { searchString in
            text = searchString
        }
    }
}

struct SearchBox_Previews: PreviewProvider {
    @State static var text = ""
    static var previews: some View {
        SearchBox(prompt: "Search for..", text: $text)
    }
}
