// TODO: NewNote, NewQuoteRepost and NewReply should be refactored. Too much copy pasta now
// TODO: Should enable undo, similar to likes or zaps
// TODO: Should add drafts and auto-save

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
        ]),
        HighlightRule(pattern: NewNoteText.typingRegex, formattingRules: [
            TextFormattingRule(key: .foregroundColor, value: UIColor(named: "AccentColor")!),
            TextFormattingRule(fontTraits: .traitBold)
        ])
    ]
    static let typingRegex = try! NSRegularExpression(pattern: "((?:^|\\s)@\\x{2063}\\x{2064}[^\\x{2063}\\x{2064}]+\\x{2064}\\x{2063}|(?<![/\\?])#)", options: [])
    static let mentionRegex = try! NSRegularExpression(pattern: "((?:^|\\s)@\\w+|(?<![/\\?])#\\S+)", options: [])
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
    let PLACEHOLDER = String(localized:"What's happening?", comment: "Placeholder text for typing a new post")
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
    var firstResults:[Contact] { Array(contacts.prefix(60)) }
    
    @State var selectedMentions:[Contact] = []
    @State var previewNRPost:NRPost?
    @State var subscriptions = Set<AnyCancellable>()
    @State var gifSheetShown = false
    
    var body: some View {
        VStack(spacing:0) {
            if let account = ns.account {
                VStack {
                    HStack(alignment: .top) {
                        PFP(pubkey: account.publicKey, account: account)
                            HighlightedTextEditor(
                                text: $vm.text,
                                pastedImages: $vm.pastedImages,
                                shouldBecomeFirstResponder: true,
                                highlightRules: NewNoteText.rules,
                                photoPickerTapped: {
                                    ipm.photoPickerShown = true
                                },
                                gifsTapped: {
                                    gifSheetShown = true
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
                                if let newImage {
                                    vm.pastedImages.append(newImage)
                                }
                            }
                            .background(alignment:.topLeading) {
                                Text(PLACEHOLDER).foregroundColor(.gray)
                                    .opacity(vm.text == "" ? 1 : 1)
                                    .offset(x: 5.0, y: 4.0)
                            }
                            .sheet(isPresented: $gifSheetShown) {
                                NavigationStack {
                                    GifSearcher { gifUrl in
                                        vm.text += gifUrl + "\n"
                                    }
                                }
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
                    if (vm.nEvent == nil) {
                        vm.nEvent = NEvent(content: newText)
                    } else {
                        vm.nEvent!.content = newText
                    }
                    
                    guard let account = ns.account else { return }
                    if let mentionTerm = mentionTerm(newText) {
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
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss() // TODO: If wrote something, confirm cancellation
                        } label: {
                            Text("Cancel")
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
                            .disabled(uploading)

                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                gifSheetShown = true
                            } label: {
                                Image("GifButton")
                            }
                            .buttonStyle(.borderless)
                            .disabled(uploading)

                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized:"Preview", comment:"Preview button when creating a new post")) {
                            guard let account = ns.account else { return }
                            guard var nEvent = vm.nEvent else { return }
                            nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected:selectedMentions)
                            nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
                            nEvent = putHashtagsInTags(nEvent)
                            nEvent.publicKey = account.publicKey
                            
                            if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                                nEvent.content = replaceNsecWithHunter2(nEvent.content)
                            }
                            for index in vm.pastedImages.indices {
                                nEvent.content = nEvent.content + "\n--@!^@\(index)@^!@--"
                            }
                            DataProvider.shared().bg.perform {
                                let previewEvent = createPreviewEvent(nEvent)
                                if (vm.pastedImages.count > 0) {
                                    previewEvent.previewImages = vm.pastedImages
                                }
                                let nrPost = NRPost(event: previewEvent)
                                DispatchQueue.main.async {
                                    self.previewNRPost = nrPost
                                }
                                DataProvider.shared().bg.delete(previewEvent)
                            }
                        }
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
                                Text("Post.verb", comment: "Button to post (publish) a new post")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .cornerRadius(20)
                        .disabled(uploading || vm.text.isEmpty)
                        
                    }
                }
                .sheet(item: $previewNRPost) { nrPost in
                    NavigationStack {
                        PostPreview(nrPost: nrPost, sendNow: self.sendNow, uploading: $uploading)
                    }
                }

                if vm.mentioning && firstResults.count > 0 {
                    ScrollView {
                        LazyVStack {
                            ForEach(firstResults) { contact in
                                ContactSearchResultRow(contact: contact) {
                                    guard vm.textView != nil else { return }
                                    let mentionName = contact.handle
                                    vm.text = "\(vm.text.dropLast(vm.term.count))\u{2063}\u{2064}\(mentionName)\u{2064}\u{2063}"
                                    selectedMentions.append(contact)
                                    vm.mentioning = false
                                    vm.lastHit = mentionName
                                    vm.term = ""
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { // after 0.3 sec to get the new .endOfDocument
                                        //                                    vm.mentioning = false
                                        let newPosition = vm.textView!.endOfDocument
                                        vm.textView!.selectedTextRange = vm.textView!.textRange(from: newPosition, to: newPosition)
                                    }
                                }
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
    }
    
//    func updateEventWithNewText() {
//        return
//        if (vm.nEvent == nil) {
//            vm.nEvent = NEvent(content: replaceMentionsWithHandles(vm.text, selected:selectedMentions))
//        } else {
//            vm.nEvent!.content = replaceMentionsWithHandles(vm.text, selected:selectedMentions)
//        }
//    }
    
    func sendNow() {
        guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
        guard var nEvent = vm.nEvent else { return }
        nEvent.createdAt = NTimestamp.init(date: Date())
        if (vm.pastedImages.count > 0) {
            uploading = true
            
            uploadImages(images: vm.pastedImages)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { result in
                    switch result {
                        case .failure(let error):
                        L.og.error("Error uploading images: \(error.localizedDescription)")
                            uploadError = "Image upload error"
                            sendNotification(.anyStatus, ("Upload error: \(error.localizedDescription)", "NewPost"))
                        case .finished:
                        L.og.debug("All images uploaded successfully")
                    }
                }, receiveValue: { urls in
                    
                    if (vm.pastedImages.count == urls.count) {
                        // send message with images
                        for url in urls {
                            nEvent.content += "\n\(url)"
                        }
                        nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected:selectedMentions)
                        nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
                        nEvent = putHashtagsInTags(nEvent)
                        
                        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                            nEvent.content = replaceNsecWithHunter2(nEvent.content)
                        }
                        if let signedEvent = try? ns.signEvent(nEvent) {
                            up.publishNow(signedEvent)
                            dismiss()
                        }
                    }
                })
                .store(in: &subscriptions)
            
            
        }
        else {
            nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected:selectedMentions)
            nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
            nEvent = putHashtagsInTags(nEvent)
            
            if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                nEvent.content = replaceNsecWithHunter2(nEvent.content)
            }
            if let signedEvent = try? ns.signEvent(nEvent) {
                up.publishNow(signedEvent)
                dismiss()
            }
        }
    }
}

struct NewNote_Previews: PreviewProvider {
    @State static var noteCancellationId:UUID?
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            NavigationStack {
                NewNote(noteCancellationId: $noteCancellationId)
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


