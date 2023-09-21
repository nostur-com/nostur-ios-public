//
//  NewQuoteRepost.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/03/2023.
//

import SwiftUI
import Combine

struct NewQuoteRepost: View {
    @EnvironmentObject private var theme:Theme
    let PLACEHOLDER = String(localized: "Add comment", comment: "Placeholder when typing a new reply")
    private var quotingEvent:Event
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = NewPostModel()
    @StateObject private var ipm = ImagePickerModel()
    
    @State var quotingNRPost:NRPost?
    
    init(quotingEvent:Event) {
        self.quotingEvent = quotingEvent
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let account = vm.activeAccount, let quotingNRPost {
                ScrollView {
                    VStack {
                        HStack(alignment: .top, spacing:0) {
                            PostAccountSwitcher(activeAccount: account, onChange: { account in
                                vm.activeAccount = account
                            })
                            .equatable()
                            .padding(.horizontal, 10)
                            
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
                                })
                            .introspect { editor in
                                if (vm.textView == nil) {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                        vm.textView = editor.textView
                                    }
                                }
                            }
                            .frame(height: 200)
                            .padding(.bottom, 10)
                            .photosPicker(isPresented: $ipm.photoPickerShown, selection: $ipm.imageSelection, matching: .images, photoLibrary: .shared())
                            .onChange(of: ipm.newImage) { newImage in
                                if let newImage {
                                    vm.pastedImages.append(newImage)
                                }
                            }
                            .background(alignment: .topLeading) {
                                Text(PLACEHOLDER).foregroundColor(.gray)
                                    .opacity(vm.text == "" ? 1 : 0)
                                    .offset(x: 5.0, y: 7.0)
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
                        ImagePreviews(pastedImages: $vm.pastedImages)
                            .padding(.leading, DIMENSIONS.ROW_PFP_SPACE - 5)
                        QuotedNoteFragmentView(nrPost: quotingNRPost)
                            .padding(.leading, DIMENSIONS.ROW_PFP_SPACE - 5)
                    }
                }
                .padding(10)
                .onChange(of: vm.debouncedText) { newText in
                    vm.textChanged(newText)
                }
                .onAppear {
                    var newQuoteRepost = NEvent(content: "")
                    newQuoteRepost.kind = .textNote
                    vm.nEvent = newQuoteRepost
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss() // TODO: If wrote something, confirm cancellation
                        }
                    }
                    
                    if let uploadError = vm.uploadError {
                        ToolbarItem(placement: .principal) {
                            Text(uploadError).foregroundColor(.red)
                        }
                    }
                    
                    if IS_CATALYST {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                ipm.photoPickerShown = true
                            } label: {
                                Image(systemName: "photo")
                            }
                            .buttonStyle(.borderless)
                            .disabled(vm.uploading)

                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                vm.gifSheetShown = true
                            } label: {
                                Image("GifButton")
                            }
                            .buttonStyle(.borderless)
                            .disabled(vm.uploading)

                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized:"Preview", comment:"Preview button when creating a new reply")) {
                            vm.showPreview(quotingEvent: quotingEvent)
                        }
                        .buttonStyle(.borderless)
                        .disabled(vm.uploading)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            vm.sendNow(quotingEvent: quotingEvent, dismiss:dismiss)
                        } label: {
                            if (vm.uploading) {
                                ProgressView()
                            }
                            else {
                                Text("Post.verb", comment: "Button to post (publish) a new reply")
                            }
                        }
                        .buttonStyle(NRButtonStyle(theme: Theme.default, style: .borderedProminent))
                        .cornerRadius(20)
                        .disabled(vm.uploading)
                    }
                }
                .sheet(item: $vm.previewNRPost) { nrPost in
                    NavigationStack {
                        PostPreview(nrPost: nrPost, sendNow: { vm.sendNow(quotingEvent: quotingEvent, dismiss:dismiss) }, uploading: $vm.uploading)
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
            vm.activeAccount = account()
        }
        .task {
            DataProvider.shared().bg.perform {
                if let quotingEventNG = quotingEvent.toBG() {
                    let quotingNRPost = NRPost(event: quotingEventNG)
                    DispatchQueue.main.async {
                        self.quotingNRPost = quotingNRPost
                    }
                }
            }
        }
    }
}

struct NewQuoteRepost_Previews: PreviewProvider {
    @State static var noteCancellationId:UUID?
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            NavigationStack {
                if let event = PreviewFetcher.fetchEvent() {
                    NewQuoteRepost(quotingEvent: event)
                }
            }
        }
    }
}

