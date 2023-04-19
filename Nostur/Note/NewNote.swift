//
//  NewNote.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI
import Combine
import PhotosUI

struct MediaImage: View {
    let imageState: ImagePickerModel.ImageState

    var body: some View {
        switch imageState {
        case .success(let image):
            image.resizable()
        case .loading:
            ProgressView()
        case .empty:
            Rectangle()
                .foregroundColor(.gray)
        case .failure:
            Rectangle()
                .foregroundColor(.gray)
        }
    }
}

class ImagePickerModel: ObservableObject {
    
    enum ImageState {
        case empty
        case loading(Progress)
        case success(Image)
        case failure(Error)
    }

    enum TransferError: Error {
        case importFailed
    }

    struct SelectedImage: Transferable {
        let image: Image
        let uiImage: UIImage

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(importedContentType: .image) { data in
            #if canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw TransferError.importFailed
                }
                let image = Image(uiImage: uiImage)
                return SelectedImage(image: image, uiImage: uiImage)
            #else
                throw TransferError.importFailed
            #endif
            }
        }
    }

    @Published var photoPickerShown = false
    @Published private(set) var imageState: ImageState = .empty

    @Published var newImage:UIImage?
    @Published var imageSelection: PhotosPickerItem? = nil {
        didSet {
            if let imageSelection {
                let progress = loadTransferable(from: imageSelection)
                imageState = .loading(progress)
            } else {
                imageState = .empty
            }
        }
    }

    // MARK: - Private Methods

    private func loadTransferable(from imageSelection: PhotosPickerItem) -> Progress {
        return imageSelection.loadTransferable(type: SelectedImage.self) { result in
            DispatchQueue.main.async {
                guard imageSelection == self.imageSelection else {
                    print("Failed to get the selected item.")
                    return
                }
                switch result {
                case .success(let selectedImage?):
                    self.imageState = .success(selectedImage.image)
                    self.newImage = selectedImage.uiImage
                case .success(nil):
                    self.imageState = .empty
                case .failure(let error):
                    self.imageState = .failure(error)
                }
            }
        }
    }
}

public final class NewNoteText: ObservableObject {
    
    @Published var mentioning = false
    @Published var text: String = ""
    @Published var pastedImages:[UIImage] = []
    @Published var debouncedText: String = ""
    @Published var term: String = ""
    @Published var nEvent:NEvent?
    @Published var lastHit:String = "NOHIT"
    @Published var textView:SystemTextView?
    
    static let rules: [HighlightRule] = [
        HighlightRule(pattern: NewNoteText.mentionRegex, formattingRules: [
            TextFormattingRule(key: .foregroundColor, value: UIColor(named: "AccentColor")!),
            TextFormattingRule(fontTraits: .traitBold)
        ])
    ]
    static let mentionRegex = try! NSRegularExpression(pattern: "(@\\w+|(?<![/\\?])#\\S+)", options: [])
    private var bag = Set<AnyCancellable>()
    
    public init(dueTime: TimeInterval = 0.2) {
        $text
            .removeDuplicates()
            .debounce(for: .seconds(dueTime), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                self?.debouncedText = value
            })
            .store(in: &bag)
    }
}

struct NewNote: View {
    let PLACEHOLDER = "What's happening?"
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ns:NosturState
    let up:Unpublisher = .shared
    @Binding var noteCancellationId:UUID?
    @State var uploading = false
    @State var uploadError:String?
    @StateObject var vm = NewNoteText()
    @StateObject var ipm = ImagePickerModel()
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Contact.nip05verifiedAt, ascending: false)], predicate: NSPredicate(value: false))
    var contacts:FetchedResults<Contact>
    var firstResults:[Contact] { Array(contacts.prefix(30)) }
    
    @State var tapOrFirstResults:[Contact] = []
    @State var previewEvent:Event?
    @State var subscriptions = Set<AnyCancellable>()
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                PFP(pubkey: ns.account!.publicKey, pictureUrl: ns.account?.picture)
                
                ZStack(alignment:.leading) {
                    VStack(alignment: .leading) {
                        Text(PLACEHOLDER).foregroundColor(.gray)
                            .opacity(vm.text == "" ? 1 : 0)
                            .offset(x: 5.0, y: 7.0)
                        Spacer()
                    }
                    VStack(alignment: .leading) {
                        HighlightedTextEditor(
                            text: $vm.text,
                            pastedImages: $vm.pastedImages,
                            shouldBecomeFirstResponder: true,
                            highlightRules: NewNoteText.rules,
                            photoPickerTapped: {
                                ipm.photoPickerShown = true
                            })
                        .introspect { editor in
                            if (vm.textView == nil) {
                                vm.textView = editor.textView
                                vm.textView?.backgroundColor = UIColor.clear
                            }
                        }
                        .frame(minHeight: 200, idealHeight: 325, maxHeight: 550, alignment: .top)
                        .photosPicker(isPresented: $ipm.photoPickerShown, selection: $ipm.imageSelection, matching: .images, photoLibrary: .shared())
                        .onChange(of: ipm.newImage) { newImage in
                            if let newImage {
                                vm.pastedImages.append(newImage)
                            }
                        }
                        ImagePreviews(pastedImages: $vm.pastedImages)
                        Spacer()
                    }
                    AnyStatus(filter: "NewPost")
                }
            }
            if vm.mentioning {
                ScrollView {
                    LazyVStack {
                        ForEach(firstResults) { contact in
                            ContactSearchResultRow(contact: contact) {
                                guard vm.textView != nil else { return }
                                let mentionName = contact.handle
                                vm.text = vm.text.dropLast(vm.term.count) + mentionName
                                tapOrFirstResults.append(contact)
                                vm.mentioning = false
                                vm.lastHit = mentionName
                                vm.term = ""
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { // after 0.02 sec to get the new .endOfDocument
                                    //                                    self.vm.mentioning = false
                                    let newPosition = vm.textView!.endOfDocument
                                    vm.textView!.selectedTextRange = vm.textView!.textRange(from: newPosition, to: newPosition)
                                }
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(10)
        .onAppear {
            updateEventWithNewText()
        }
        .onChange(of: firstResults) { newResults in
            guard newResults.count > 0 else { return }
            if let exactResult = newResults.first(where: { $0.handle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == vm.term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }) {
                tapOrFirstResults.insert(exactResult, at:0)
                updateEventWithNewText()
            }
        }
        .onChange(of: vm.debouncedText) { mentionString in
            guard let account = ns.account else { return }
            
            if let mentionTerm = mentionTerm(mentionString) {
                print ("mentionTerm \(mentionTerm) lastHit: \(vm.lastHit)")
                
                if mentionTerm == vm.lastHit {
                    vm.mentioning = false
                }
                else {
                    vm.mentioning = true
                    vm.term = mentionTerm
                    contacts.nsPredicate = NSPredicate(format: "(display_name CONTAINS[cd] %@ OR name CONTAINS[cd] %@) AND NOT pubkey IN %@", mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), account.blockedPubkeys_)
                }
            }
            else {
                vm.mentioning = false
            }
            
            updateEventWithNewText()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss() // TODO: If wrote something, confirm cancellation
                } label: {
                    Text("Cancel")
                }
            }
            ToolbarItem {
                Button("Preview") {
                    guard let account = ns.account else { return }
                    guard var nEvent = vm.nEvent else { return }
                    nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
                    nEvent = putHashtagsInTags(nEvent)
                    nEvent.publicKey = account.publicKey
                    
                    if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                        nEvent.content = replaceNsecWithHunter2(nEvent.content)
                    }
                    for index in vm.pastedImages.indices {
                        nEvent.content = nEvent.content + "\n--@!^@\(index)@^!@--"
                    }
                    let previewEvent = createPreviewEvent(nEvent)
                    if (vm.pastedImages.count > 0) {
                        previewEvent.previewImages = vm.pastedImages
                    }
                    self.previewEvent = previewEvent
                }
                .cornerRadius(20)
                .disabled(uploading)
            }
            
            if let uploadError {
                ToolbarItem(placement: .principal) {
                    Text(uploadError).foregroundColor(.red)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sendNow()
                } label: {
                    if (uploading) {
                        ProgressView()
                    }
                    else {
                        Text("Post")
                    }
                }
                .buttonStyle(.borderedProminent)
                .cornerRadius(20)
                .disabled(uploading)
                    
            }
        }
        .sheet(item: $previewEvent) { previewEvent in
            NavigationStack {
                PostPreview(previewEvent: previewEvent, sendNow: self.sendNow)
                    .onDisappear {
                        DataProvider.shared().viewContext.delete(previewEvent)
                    }
            }
        }
    }
    
    // Replaces "@handles in text with @npubs", which will later be replaced with #[index], and in a future update with nostr:..
    func updateEventWithNewText() {
        var textToReplaceWithNpubs = vm.text
        for contact in tapOrFirstResults.sorted(by: { $0.handle.count > $1.handle.count }) { // .count so we replace @TestMacOS before partial match @test
            textToReplaceWithNpubs = textToReplaceWithNpubs.replacingOccurrences(of: "@\(contact.handle)", with: "@\(contact.npub)", options: .caseInsensitive)
        }
        if (vm.nEvent == nil) {
            vm.nEvent = NEvent(content: textToReplaceWithNpubs)
        } else {
            vm.nEvent!.content = textToReplaceWithNpubs
        }
    }
    
    func sendNow() {
        guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
        guard var nEvent = vm.nEvent else { return }
        
        if (vm.pastedImages.count > 0) {
            uploading = true
            
            uploadImages(images: vm.pastedImages)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { result in
                    switch result {
                        case .failure(let error):
                            print("Error uploading images: \(error.localizedDescription)")
                            uploadError = "Image upload error"
                            sendNotification(.anyStatus, ("Upload error: \(error.localizedDescription)", "NewPost"))
                        case .finished:
                            print("All images uploaded successfully")
                    }
                }, receiveValue: { urls in
                    
                    if (vm.pastedImages.count == urls.count) {
                        // send message with images
                        for url in urls {
                            nEvent.content += "\n\(url)"
                        }
                        nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
                        nEvent = putHashtagsInTags(nEvent)
                        
                        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                            nEvent.content = replaceNsecWithHunter2(nEvent.content)
                        }
                        if let signedEvent = try? ns.signEvent(nEvent) {
                            //                        print(signedEvent.wrappedEventJson())
                            up.publishNow(signedEvent)
                            //                        noteCancellationId = up.publish(signedEvent)
                            dismiss()
                            previewEvent = nil
                        }
                    }
//                    print("Uploaded image URLs: \(urls)")
                })
                .store(in: &subscriptions)
            
            
        }
        else {
            nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
            nEvent = putHashtagsInTags(nEvent)
            
            if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                nEvent.content = replaceNsecWithHunter2(nEvent.content)
            }
            if let signedEvent = try? ns.signEvent(nEvent) {
                //                        print(signedEvent.wrappedEventJson())
                up.publishNow(signedEvent)
                //                        noteCancellationId = up.publish(signedEvent)
                dismiss()
                previewEvent = nil
            }
        }
    }
}

struct NewNote_Previews: PreviewProvider {
    @State static var noteCancellationId:UUID?
    static var previews: some View {
        NavigationStack {
            NewNote(noteCancellationId: $noteCancellationId)
        }
        .withPreviewEnvironment()
    }
}

func mentionTerm(_ text:String) -> String? {
    if let rangeStart = text.lastIndex(of: Character("@")) {
        let extractedString = String(text[rangeStart..<text.endIndex].dropFirst(1))
        return extractedString
    }
    return nil
}


