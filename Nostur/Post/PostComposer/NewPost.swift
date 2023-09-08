//
//  NewPost.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

// TODO: Should enable undo, similar to likes or zaps
// TODO: Should add drafts and auto-save
// TODO: Need to create better solution for typing @mentions

import SwiftUI
import Combine
import PhotosUI

struct NewPost: View {
    @EnvironmentObject var theme:Theme
    let PLACEHOLDER = String(localized:"What's happening?", comment: "Placeholder text for typing a new post")
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ns:NosturState
    let up:Unpublisher = .shared
    
    @StateObject var vm = NewPostModel()
    @StateObject var ipm = ImagePickerModel()
    
    var body: some View {
        VStack(spacing:0) {
            if let account = vm.activeAccount {
                VStack {
                    HStack(alignment: .top) {
                        PostAccountSwitcher(activeAccount: account, onChange: { account in
                            vm.activeAccount = account
                        })
                        HighlightedTextEditor(
                            text: $vm.text,
                            pastedImages: $vm.pastedImages,
                            shouldBecomeFirstResponder: true,
                            highlightRules: NewPostModel.rules,
                            photoPickerTapped: {
                                ipm.photoPickerShown = true
                            },
                            gifsTapped: {
                                vm.gifSheetShown = true
                            }
                        )
                        .introspect { editor in
                            if (vm.textView == nil) {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                    vm.textView = editor.textView
                                }
                            }
                        }
                        .photosPicker(isPresented: $ipm.photoPickerShown, selection: $ipm.imageSelection, matching: .images, photoLibrary: .shared())
                        .onChange(of: ipm.newImage) { newImage in
                            if let newImage { vm.pastedImages.append(newImage) }
                        }
                        .background(alignment:.topLeading) {
                            Text(PLACEHOLDER).foregroundColor(.gray)
                                .opacity(vm.text == "" ? 1 : 1)
                                .offset(x: 5.0, y: 4.0)
                        }
                        .sheet(isPresented: $vm.gifSheetShown) {
                            NavigationStack {
                                GifSearcher { gifUrl in
                                    vm.text += gifUrl + "\n"
                                }
                            }
                            .presentationBackground(theme.background)
                        }
                        AnyStatus(filter: "NewPost")
                    }
                    HStack {
                        ImagePreviews(pastedImages: $vm.pastedImages)
                            .padding(.leading, DIMENSIONS.ROW_PFP_SPACE - 5)
                    }
                }
                .padding(10)
                .onChange(of: vm.debouncedText) { newText in
                    vm.textChanged(newText)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { dismiss() } label: { Text("Cancel") }
                    }
                    if IS_CATALYST {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button { ipm.photoPickerShown = true } label: {
                                Image(systemName: "photo")
                            }
                            .buttonStyle(.borderless)
                            .disabled(vm.uploading)

                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button { vm.gifSheetShown = true } label: {
                                Image("GifButton")
                            }
                            .buttonStyle(.borderless)
                            .disabled(vm.uploading)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized:"Preview", comment:"Preview button when creating a new post")) {
                            vm.showPreview()
                        }
                        .disabled(vm.uploading)
                    }
                    
                    if let uploadError = vm.uploadError {
                        ToolbarItem(placement: .principal) {
                            Text(uploadError).foregroundColor(.red)
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { vm.sendNow(dismiss:dismiss) } label: {
                            if (vm.uploading) {
                                ProgressView()
                            }
                            else {
                                Text("Post.verb", comment: "Button to post (publish) a new post")
                            }
                        }
                        .buttonStyle(NRButtonStyle(theme: Theme.default, style: .borderedProminent))
                        .cornerRadius(20)
                        .disabled(vm.uploading || vm.text.isEmpty)
                        
                    }
                }
                .sheet(item: $vm.previewNRPost) { nrPost in
                    NavigationStack {
                        PostPreview(nrPost: nrPost, sendNow: { vm.sendNow(dismiss:dismiss) }, uploading: $vm.uploading)
                    }
                    .presentationBackground(theme.background)
                }

                if vm.mentioning && !vm.filteredContactSearchResults.isEmpty {
                    ScrollView {
                        LazyVStack {
                            ForEach(vm.filteredContactSearchResults) { contact in
                                ContactSearchResultRow(contact: contact, onSelect: {
                                    vm.selectContactSearchResult(contact)
                                })
                            }
                        }
                    }
                    .padding()
                }
            }
            else {
                ProgressView()
            }
        }
        .onAppear {
            vm.activeAccount = NosturState.shared.account
        }
    }
}

struct NewNote_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadAccounts()
            pe.loadPosts()
            pe.loadContacts()
        }) {
            NavigationStack {
                NewPost()
            }
        }
    }
}

func mentionTerm(_ text:String) -> String? {
    if let rangeStart = text.lastIndex(of: Character("@")) {
        let extractedString = String(text[rangeStart..<text.endIndex].dropFirst(1))
        return extractedString
    }
    return nil
}


