//
//  MutedWords.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/04/2023.
//

import SwiftUI
import NavigationBackport

struct MutedWordsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(value: true))
    var mutedWords:FetchedResults<MutedWords>
    
    @State var selected:MutedWords?
    
    var body: some View {
        NXForm {
            ForEach(mutedWords) { mutedWord in
                Text(mutedWord.words == "" ? "Tap to edit..." : mutedWord.words ?? "Tap to edit...")
                    .onTapGesture {
                        selected = mutedWord
                    }
            }
            .onDelete { offsets in
                offsets.forEach { viewContext.delete(mutedWords[$0]) }
                DataProvider.shared().saveToDiskNow(.viewContext)
                AppState.shared.loadMutedWords()
            }
        }
        .sheet(item: $selected) { words in
            EditWordSheet(mutedWords: words)
                .presentationBackgroundCompat(theme.listBackground)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", systemImage: "plus") {
                    let m = MutedWords(context: viewContext)
                    m.words = ""
                }
            }
        }
    }
    
    struct EditWordSheet: View {
        @Environment(\.dismiss) var dismiss
        @ObservedObject var mutedWords: MutedWords
        @State var text: String
        init(mutedWords: MutedWords) {
            self.mutedWords = mutedWords
            _text = State(initialValue: mutedWords.words ?? "")
        }
        
        var body: some View {
            NBNavigationStack {
                NXForm {
                    Section(header: Text("Specific word or sentence", comment: "Heading for entering a word or sentence to mute"), footer: Text("Posts containing this will be filtered from your feed")) {
                        TextField("Specific word or sentence", text: $text, prompt: Text(verbatim: "nft"))
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                        
                        Toggle(isOn: $mutedWords.enabled) {
                            Text("Activate this filter", comment: "Toggle to activate filter")
                        }
                    }
                }
                .navigationTitle(String(localized:"Edit muted word", comment: "Navigation title for screen to edit muted word"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", systemImage: "checkmark") {
                            mutedWords.words = text
                            DataProvider.shared().saveToDiskNow(.viewContext)
                            AppState.shared.loadMutedWords()
                            dismiss()
                        }
                        .buttonStyleGlassProminent()
                    }
                }
            }
            .nbUseNavigationStack(.never)
        }
    }
}

struct MutedWordsView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadBlockedAndMuted()
        }) {
            NBNavigationStack {
                MutedWordsView()
            }
        }
    }
}
