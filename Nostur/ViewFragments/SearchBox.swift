//
//  SearchBox.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/05/2023.
//

import SwiftUI

struct SearchBox: View {
    @EnvironmentObject private var themes: Themes
    @StateObject var debounceObject = DebounceObject()
    var prompt: String
    @Binding var text: String
    var autoFocus: Bool = true
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField(text: $debounceObject.text, prompt: Text(prompt).foregroundColor(Color.secondary), label: {
            Text(prompt)
        })
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .focused($isFocused)
        .onAppear {
            guard autoFocus else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFocused = true
            }
        }
        .padding(10)
        .padding(.leading, 25)
        .padding(.trailing, 25)
        .background {
            themes.theme.background.opacity(0.5)
                .overlay(alignment:.leading) {
                    Image(systemName: "magnifyingglass")
                        .imageScale(.medium)
                        .foregroundColor(Color.secondary)
                        .padding(.leading, 10)
                }
        }
        .overlay(alignment:.trailing) {
            if debounceObject.text != "" {
                Image(systemName: "multiply.circle.fill")
                    .imageScale(.medium)
                    .foregroundColor(Color.secondary)
                    .padding(.leading, 10)
                    .padding(.trailing, 5)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        debounceObject.text = ""
                    }
            }
        }
        .cornerRadius(8.0)
        .onChange(of: text) { newText in
            if newText != debounceObject.text {
                debounceObject.text = newText
            }
        }
        .onChange(of: debounceObject.debouncedText) { searchString in
            if searchString != text {
                text = searchString
            }
        }
    }
}

import NavigationBackport

struct SearchBox_Previews: PreviewProvider {
    @State static var text = ""
    static var previews: some View {
        NBNavigationStack {
            VStack {
                SearchBox(prompt: "SearchBox in view..", text: $text)
                    .padding()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SearchBox(prompt: "SearchBox in toolbar..", text: $text)
                        .padding()
                }
            }
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
        .environmentObject(Themes.default)
    }
}

//@available(iOS 18.0, *)
//#Preview {
//    
//    @Previewable @State var text = ""
//    
//    VStack {
//        SearchBox(prompt: "SearchBox in view..", text: $text)
//            .padding()
//    }
//    .toolbar {
//        ToolbarItem(placement: .principal) {
//            SearchBox(prompt: "SearchBox in toolbar..", text: $text)
//                .padding()
//        }
//    }
//}

