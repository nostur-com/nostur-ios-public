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
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.words, order: .forward)], predicate: NSPredicate(value: true))
    var mutedWords: FetchedResults<MutedWords>
    
    @State var selected: MutedWords?
    @State private var isShowingAddSheet = false
    
    var body: some View {
        List {
            ForEach(mutedWords) { mutedWord in
                Box {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text((mutedWord.words ?? "").isEmpty ? String(localized: "Tap to edit...") : (mutedWord.words ?? ""))
                                .foregroundStyle(.primary)
                            
                            Text(mutedWord.enabled
                                 ? String(localized: "Active")
                                 : String(localized: "Disabled"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(mutedWord.enabled ? String(localized: "On") : String(localized: "Off"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selected = mutedWord
                    }
                    .background(theme.listBackground)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(theme.listBackground)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                .padding(.bottom, GUTTER)
            }
            .onDelete { offsets in
                offsets.forEach { viewContext.delete(mutedWords[$0]) }
                DataProvider.shared().saveToDiskNow(.viewContext)
                AppState.shared.loadMutedWords()
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 50)
        .sheet(item: $selected) { words in
            EditWordSheet(mutedWords: words)
                .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddWordSheet()
                .presentationBackgroundCompat(theme.listBackground)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", systemImage: "plus") {
                    isShowingAddSheet = true
                }
            }
        }
        .background(theme.listBackground)
    }
    
    struct EditWordSheet: View {
        @Environment(\.dismiss) var dismiss
        @ObservedObject var mutedWords: MutedWords
        @State var text: String
        @State var enabled: Bool

        private var trimmedText: String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        init(mutedWords: MutedWords) {
            self.mutedWords = mutedWords
            _text = State(initialValue: mutedWords.words ?? "")
            _enabled = State(initialValue: mutedWords.enabled)
        }
        
        var body: some View {
            NBNavigationStack {
                NXForm {
                    Section(header: Text("Specific word or sentence", comment: "Heading for entering a word or sentence to mute"), footer: Text("Posts containing this will be filtered from your feed")) {
                        TextField("Specific word or sentence", text: $text, prompt: Text(verbatim: "nft"))
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                        
                        Toggle(isOn: $enabled) {
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
                            mutedWords.words = trimmedText
                            mutedWords.enabled = enabled
                            DataProvider.shared().saveToDiskNow(.viewContext)
                            AppState.shared.loadMutedWords()
                            dismiss()
                        }
                        .disabled(trimmedText.isEmpty)
                        .buttonStyleGlassProminent()
                    }
                }
            }
            .nbUseNavigationStack(.never)
        }
    }

    struct AddWordSheet: View {
        @Environment(\.dismiss) var dismiss
        @Environment(\.managedObjectContext) private var viewContext
        @State private var text = ""
        @State private var enabled = true

        private var trimmedText: String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var body: some View {
            NBNavigationStack {
                NXForm {
                    Section(header: Text("Specific word or sentence", comment: "Heading for entering a word or sentence to mute"), footer: Text("Posts containing this will be filtered from your feed")) {
                        TextField("Specific word or sentence", text: $text, prompt: Text(verbatim: "nft"))
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)

                        Toggle(isOn: $enabled) {
                            Text("Activate this filter", comment: "Toggle to activate filter")
                        }
                    }
                }
                .navigationTitle(String(localized: "Add muted word", comment: "Navigation title for screen to add muted word"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", systemImage: "checkmark") {
                            let m = MutedWords(context: viewContext)
                            m.words = trimmedText
                            m.enabled = enabled
                            DataProvider.shared().saveToDiskNow(.viewContext)
                            AppState.shared.loadMutedWords()
                            dismiss()
                        }
                        .disabled(trimmedText.isEmpty)
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
