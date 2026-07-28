#if os(iOS)
//
//  HighlightedTextEditor.UIKit.swift
//
//
//  Created by Kyle Nazario on 5/26/21.
//  Modified by Fabian Lachman 2023

import SwiftUI
import UIKit

extension NSAttributedString.Key {
    static let nosturMentionPubkey = NSAttributedString.Key("com.nostur.composer.mention-pubkey")
}

struct NosturMentionAttributeRun {
    let pubkey: String
    let range: NSRange
    let text: String
}

extension NSAttributedString {
    func nosturMentionRuns() -> [NosturMentionAttributeRun] {
        guard length > 0 else { return [] }

        var runs: [NosturMentionAttributeRun] = []
        enumerateAttribute(
            .nosturMentionPubkey,
            in: NSRange(location: 0, length: length)
        ) { value, range, _ in
            guard let pubkey = value as? String else { return }
            runs.append(NosturMentionAttributeRun(
                pubkey: pubkey,
                range: range,
                text: attributedSubstring(from: range).string
            ))
        }
        return runs
    }
}

public typealias PhotoPickerTappedCallback = () -> Void
public typealias VideoPickerTappedCallback = () -> Void
public typealias GifsTappedCallback = () -> Void
public typealias CameraTappedCallback = () -> Void
public typealias NestsTappedCallback = () -> Void
public typealias VoiceMessageTappedCallback = () -> Void
public typealias PrivateReplyTappedCallback = () -> Void

protocol PastedMediaDelegate: UITextViewDelegate {
    func didPasteImage(_ image: UIImage)
    func didPasteGif(_ data: Data)
    func didPasteVideo(_ video: URL)
    
    func didPastePlaceholderForGif(_ info: (UIImage, UUID))
    func didFetchActualGif(_ info: (Data, UUID))
    
    func photoPickerTapped()
    func videoTapped()
    func gifsTapped()
    func cameraTapped()
    func nestsTapped()
    func voiceMessageTapped()
    func privateReplyTapped()
}

class NosturTextView: UITextView {
    var pastedMediaDelegate: PastedMediaDelegate?

    override var delegate: UITextViewDelegate? {
        get { pastedMediaDelegate }
        set { pastedMediaDelegate = newValue as? PastedMediaDelegate }
    }

    // This gets called when user presses menu "Paste" option
    override func paste(_ sender: Any?) {
        if let gifData = UIPasteboard.general.data(forPasteboardType: "com.compuserve.gif") {
            pastedMediaDelegate?.didPasteGif(gifData)
        }
        else if let url = UIPasteboard.general.value(forPasteboardType: "public.url") as? URL, url.absoluteString.hasSuffix(".gif") {
            if let image = UIPasteboard.general.image { // First get placeholder image
                let placeholderId = UUID()
                pastedMediaDelegate?.didPastePlaceholderForGif((image, placeholderId))
                
                // then fetch gif
                URLSession.shared.dataTask(with: url) { data, response, error in
                    if let data = data {
                        DispatchQueue.main.async {
                            self.pastedMediaDelegate?.didFetchActualGif((data, placeholderId))
                        }
                    }
                }.resume()
            } // no placeholder image? probably pasting something else then
            else {
                super.paste(sender)
            }
        }
        else if let image = UIPasteboard.general.image {
            pastedMediaDelegate?.didPasteImage(image)
        }
        else {
            // Call the normal paste action
            super.paste(sender)
        }
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) && UIPasteboard.general.image != nil {
            return true
        } else {
            return super.canPerformAction(action, withSender: sender)
        }
    }
    
    @objc func photoPickerTapped() {
        pastedMediaDelegate?.photoPickerTapped()
    }
    
    @objc func videoTapped() {
        pastedMediaDelegate?.videoTapped()
    }
    
    @objc func gifsTapped() {
        pastedMediaDelegate?.gifsTapped()
    }
    
    @objc func cameraTapped() {
        pastedMediaDelegate?.cameraTapped()
    }
    
    @objc func nestsTapped() {
        pastedMediaDelegate?.nestsTapped()
    }
    
    @objc func voiceMessageTapped() {
        pastedMediaDelegate?.voiceMessageTapped()
    }
    
    @objc func privateReplyTapped() {
        pastedMediaDelegate?.privateReplyTapped()
    }
    
    
}

extension UITextView {
    /// Replaces editor content using TextKit's backing storage and moves the
    /// insertion point using UTF-16 offsets, matching NSRange and UITextView.
    @discardableResult
    func replaceTextStorageCharacters(
        in range: NSRange,
        with replacement: String,
        undoActionName: String? = nil
    ) -> NSRange? {
        replaceTextStorageCharacters(
            in: range,
            with: NSAttributedString(string: replacement),
            undoActionName: undoActionName
        )
    }

    /// Attributed replacement variant used for semantic composer tokens.
    @discardableResult
    func replaceTextStorageCharacters(
        in range: NSRange,
        with replacement: NSAttributedString,
        undoActionName: String? = nil
    ) -> NSRange? {
        guard markedTextRange == nil else { return nil }
        guard range.location <= textStorage.length,
              range.length <= textStorage.length - range.location else { return nil }

        let replacedText = textStorage.attributedSubstring(from: range)
        let selectionBeforeReplacement = selectedRange
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: replacement)
        textStorage.endEditing()

        let insertionPoint = NSRange(
            location: range.location + replacement.length,
            length: 0
        )
        selectedRange = insertionPoint

        if let undoActionName, let undoManager {
            let undoRange = NSRange(location: range.location, length: replacement.length)
            undoManager.registerUndo(withTarget: self) { textView in
                _ = textView.replaceTextStorageCharacters(
                    in: undoRange,
                    with: replacedText,
                    undoActionName: undoActionName
                )
                textView.selectedRange = selectionBeforeReplacement
            }
            undoManager.setActionName(undoActionName)
        }
        return insertionPoint
    }
}

public struct HighlightedTextEditor: UIViewRepresentable, HighlightingTextEditor {
    
    public struct Internals {
        public let textView: SystemTextView
        public let scrollView: SystemScrollView?
    }
    
    @Binding var text: String
    
    @Binding var pastedImages: [PostedImageMeta]
    @Binding var pastedVideos: [PostedVideoMeta]
    @Binding var showVoiceRecorderButton: Bool
    
    var shouldBecomeFirstResponder: Bool
    
    let textView = NosturTextView()
    let highlightRules: [HighlightRule]
    var photoPickerTapped: PhotoPickerTappedCallback?
    var videoPickerTapped: VideoPickerTappedCallback?
    var gifsTapped: GifsTappedCallback?
    var cameraTapped: CameraTappedCallback?
    var nestsTapped: NestsTappedCallback?
    var voiceMessageTapped: VoiceMessageTappedCallback?
    var privateReplyTapped: PrivateReplyTappedCallback?
    var isPrivateReplyActive: Bool
    var isPrivateReplyLocked: Bool
    var kind: NEventKind?
    
    private(set) var onEditingChanged: OnEditingChangedCallback?
    private(set) var onCommit: OnCommitCallback?
    private(set) var introspect: IntrospectCallback?
    
    public init(
        text: Binding<String>,
        kind: NEventKind? = nil,
        showVoiceRecorderButton: Binding<Bool>,
        pastedImages: Binding<[PostedImageMeta]>,
        pastedVideos: Binding<[PostedVideoMeta]>,
        shouldBecomeFirstResponder: Bool,
        highlightRules: [HighlightRule],
        photoPickerTapped: PhotoPickerTappedCallback? = nil,
        videoPickerTapped: VideoPickerTappedCallback? = nil,
        gifsTapped: GifsTappedCallback? = nil,
        cameraTapped: CameraTappedCallback? = nil,
        nestsTapped: NestsTappedCallback? = nil,
        voiceMessageTapped: VoiceMessageTappedCallback? = nil,
        privateReplyTapped: PrivateReplyTappedCallback? = nil,
        isPrivateReplyActive: Bool = false,
        isPrivateReplyLocked: Bool = false
    ) {
        _text = text
        _showVoiceRecorderButton = showVoiceRecorderButton
        _pastedImages = pastedImages
        _pastedVideos = pastedVideos
        self.shouldBecomeFirstResponder = shouldBecomeFirstResponder
        self.highlightRules = highlightRules
        self.photoPickerTapped = photoPickerTapped
        self.videoPickerTapped = videoPickerTapped
        self.gifsTapped = gifsTapped
        self.cameraTapped = cameraTapped
        self.nestsTapped = nestsTapped
        self.voiceMessageTapped = voiceMessageTapped
        self.privateReplyTapped = privateReplyTapped
        self.isPrivateReplyActive = isPrivateReplyActive
        self.isPrivateReplyLocked = isPrivateReplyLocked
        self.kind = kind
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIView(context: Context) -> UITextView {
//        _ = textView.layoutManager // force an UITextView to fallback to Text Kit 1 - Maybe fixes crashes on iOS17 beta
        
        if #available(iOS 17.0, *) {
            // Local edits no longer replace the full attributed string, so the
            // system can safely manage inline prediction state.
            textView.inlinePredictionType = .default
        }
        
        textView.smartInsertDeleteType = .no
        textView.isScrollEnabled = true
        textView.backgroundColor = UIColor.clear
        textView.delegate = context.coordinator
        textView.pastedMediaDelegate = context.coordinator
        if kind != .shortVideos {
            if #available(iOS 26.0, *) {
                makeToolbar26(textView, context: context)
            }
            else {
                makeToolbar(textView, context: context)
            }
        }
        textView.font = UIFont.nosturBody()
        textView.adjustsFontForContentSizeCategory = true
        
        updateTextViewModifiers(textView)
        if (shouldBecomeFirstResponder) {
            textView.becomeFirstResponder()
        }
        return textView
    }
    
    public func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.isScrollEnabled = false
        context.coordinator.updatingUIView = true
        context.coordinator.parent = self
        uiView.font = UIFont.nosturBody()
        
        uiView.backgroundColor = text.isEmpty ? UIColor.clear : UIColor(Themes.default.theme.listBackground)
        
        // Only turn off, never turn on
        if !showVoiceRecorderButton && context.coordinator.isShowingVoiceRecorderButton {
            if #available(iOS 26.0, *) {
                makeToolbar26(uiView, context: context)
            }
            else {
                makeToolbar(uiView, context: context)
            }
            context.coordinator.isShowingVoiceRecorderButton = false
            
            // Force the text view to reload its input accessory view or button doesn't go away
            uiView.reloadInputViews()
        }

        let hasPrivateReplyAction = privateReplyTapped != nil
        let didPrivateReplyActionChange = context.coordinator.lastHasPrivateReplyAction != hasPrivateReplyAction
        let didPrivateReplyStateChange =
            context.coordinator.lastPrivateReplyActive != isPrivateReplyActive ||
            context.coordinator.lastPrivateReplyLocked != isPrivateReplyLocked

        if didPrivateReplyActionChange || didPrivateReplyStateChange {
            if #available(iOS 26.0, *) {
                makeToolbar26(uiView, context: context)
            }
            else {
                makeToolbar(uiView, context: context)
            }
            context.coordinator.lastHasPrivateReplyAction = hasPrivateReplyAction
            context.coordinator.lastPrivateReplyActive = isPrivateReplyActive
            context.coordinator.lastPrivateReplyLocked = isPrivateReplyLocked

            // Refresh toolbar button icon and enabled state when private reply availability changes.
            uiView.reloadInputViews()
        }
        
        // While the user is editing, UITextView owns its text storage. SwiftUI
        // updates normally echo text that is already in the view, so only replace
        // characters when the binding contains a genuine external change.
        if uiView.markedTextRange == nil {
            if uiView.text != text {
                let mentionRuns = uiView.attributedText.nosturMentionRuns()
                let highlightedText = HighlightedTextEditor.getHighlightedText(
                    text: text,
                    highlightRules: highlightRules
                )
                uiView.textStorage.setAttributedString(highlightedText)
                context.coordinator.restoreMentionRuns(mentionRuns, in: uiView)
                context.coordinator.didHighlightAllText(text)
            } else {
                context.coordinator.applyHighlighting(to: uiView)
            }
        }
        updateTextViewModifiers(uiView)
        runIntrospect(uiView)
        uiView.isScrollEnabled = true
        if let selectedRange = context.coordinator.selectedRange {
            let textLength = uiView.attributedText.length
            let location = min(selectedRange.location, textLength)
            let length = min(selectedRange.length, textLength - location)
            uiView.selectedRange = NSRange(location: location, length: length)
        }
        context.coordinator.updatingUIView = false
    }
    
    private func runIntrospect(_ textView: UITextView) {
        guard let introspect = introspect else { return }
        let internals = Internals(textView: textView, scrollView: nil)
        introspect(internals)
    }
    
    private func updateTextViewModifiers(_ textView: UITextView) {
        // BUGFIX #19: https://stackoverflow.com/questions/60537039/change-prompt-color-for-uitextfield-on-mac-catalyst
        let textInputTraits = textView.value(forKey: "textInputTraits") as? NSObject
        textInputTraits?.setValue(textView.tintColor, forKey: "insertionPointColor")
    }
    
    @available(iOS 26.0, *)
    private func makeToolbar26(_ uiView: UITextView, context: Context) {
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        flexibleSpace.hidesSharedBackground = false
        
        var barButtons: [UIBarButtonItem] = []
        
        if privateReplyTapped != nil {
            let privateReplyButton = UIButton(type: .system)
            privateReplyButton.setImage(UIImage(systemName: isPrivateReplyActive ? "lock.fill" : "lock.open"), for: .normal)
            privateReplyButton.tintColor = UIColor(Themes.default.theme.accent)
            privateReplyButton.isEnabled = !isPrivateReplyLocked
            privateReplyButton.addTarget(self, action: #selector(textView.privateReplyTapped), for: .touchUpInside)
            let privateReply = UIBarButtonItem(customView: privateReplyButton)
            barButtons.append(privateReply)
        }
        
        if showVoiceRecorderButton {
            let voiceRecordingButton = UIButton(type: .system)
            voiceRecordingButton.setImage(UIImage(systemName: "mic"), for: .normal)
            voiceRecordingButton.tintColor = UIColor(Themes.default.theme.accent)
            voiceRecordingButton.addTarget(self, action: #selector(textView.voiceMessageTapped), for: .touchUpInside)
            let voiceRecording = UIBarButtonItem(customView: voiceRecordingButton)
            barButtons.append(voiceRecording)
        }
        
        if kind != .shortVideos && kind != .picture && kind != .highlight {
            let nestsButton = UIButton(type: .system)
            nestsButton.setImage(UIImage(systemName: "dot.radiowaves.left.and.right"), for: .normal)
            nestsButton.tintColor = UIColor(Themes.default.theme.accent)
            nestsButton.addTarget(self, action: #selector(textView.nestsTapped), for: .touchUpInside)
            let nests = UIBarButtonItem(customView: nestsButton)
            barButtons.append(nests)
        }
        
        let cameraButton = UIButton(type: .system)
        cameraButton.setImage(UIImage(systemName: "camera"), for: .normal)
        cameraButton.tintColor = UIColor(Themes.default.theme.accent)
        cameraButton.addTarget(self, action: #selector(textView.cameraTapped), for: .touchUpInside)
        let camera = UIBarButtonItem(customView: cameraButton)
        barButtons.append(camera)
        
        let photoButton = UIButton(type: .system)
        photoButton.setImage(UIImage(systemName: "photo"), for: .normal)
        photoButton.tintColor = UIColor(Themes.default.theme.accent)
        photoButton.addTarget(self, action: #selector(textView.photoPickerTapped), for: .touchUpInside)
        let photos = UIBarButtonItem(customView: photoButton)
        barButtons.append(photos)
        
        if kind != .shortVideos && kind != .picture {
            let videoButton = UIButton(type: .system)
            videoButton.setImage(UIImage(systemName: "video"), for: .normal)
            videoButton.tintColor = UIColor(Themes.default.theme.accent)
            videoButton.addTarget(self, action: #selector(textView.videoTapped), for: .touchUpInside)
            let videos = UIBarButtonItem(customView: videoButton)
            barButtons.append(videos)
            
            
            let gifButton = UIButton(type: .system)
            gifButton.setImage(UIImage(named: "GifButton"), for: .normal)
            gifButton.tintColor = UIColor(Themes.default.theme.accent)
        
            gifButton.imageView?.contentMode = .scaleAspectFit
            gifButton.sizeToFit()
            
            gifButton.addTarget(self, action: #selector(textView.gifsTapped), for: .touchUpInside)
            let gifs = UIBarButtonItem(customView: gifButton)
            barButtons.append(gifs)
        }
        
        
        let doneToolbar: UIToolbar = UIToolbar(frame: CGRect.init(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        doneToolbar.barStyle = .default
        
        barButtons.append(flexibleSpace) // last
        
        doneToolbar.setItems(barButtons, animated: false)
        
        uiView.inputAccessoryView = doneToolbar
    }
    
    private func makeToolbar(_ uiView: UITextView, context: Context) {
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        let fixedSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpace.width = 9
        
        var barButtons: [UIBarButtonItem] = []
        
        if privateReplyTapped != nil {
            let privateReplyButton = UIButton(type: .system)
            privateReplyButton.setImage(UIImage(systemName: isPrivateReplyActive ? "lock.fill" : "lock.open"), for: .normal)
            privateReplyButton.tintColor = UIColor(Themes.default.theme.accent)
            privateReplyButton.isEnabled = !isPrivateReplyLocked
            privateReplyButton.addTarget(self, action: #selector(textView.privateReplyTapped), for: .touchUpInside)
            let privateReply = UIBarButtonItem(customView: privateReplyButton)
            barButtons.append(privateReply)
        }
        
        if showVoiceRecorderButton {
            let voiceRecordingButton = UIButton(type: .system)
            voiceRecordingButton.setImage(UIImage(systemName: "mic"), for: .normal)
            voiceRecordingButton.tintColor = UIColor(Themes.default.theme.accent)
            voiceRecordingButton.addTarget(self, action: #selector(textView.voiceMessageTapped), for: .touchUpInside)
            let voiceRecording = UIBarButtonItem(customView: voiceRecordingButton)
            
            if barButtons.count != 0 {
                barButtons.append(fixedSpace)
            }
            barButtons.append(voiceRecording)
        }
        
        if kind != .shortVideos && kind != .picture && kind != .highlight {
            let nestsButton = UIButton(type: .system)
            nestsButton.setImage(UIImage(systemName: "dot.radiowaves.left.and.right"), for: .normal)
            nestsButton.tintColor = UIColor(Themes.default.theme.accent)
            nestsButton.addTarget(self, action: #selector(textView.nestsTapped), for: .touchUpInside)
            let nests = UIBarButtonItem(customView: nestsButton)
            
            if barButtons.count != 0 {
                barButtons.append(fixedSpace)
            }
            barButtons.append(nests)
        }
        
        let cameraButton = UIButton(type: .system)
        cameraButton.setImage(UIImage(systemName: "camera"), for: .normal)
        cameraButton.tintColor = UIColor(Themes.default.theme.accent)
        cameraButton.addTarget(self, action: #selector(textView.cameraTapped), for: .touchUpInside)
        let camera = UIBarButtonItem(customView: cameraButton)
        
        if barButtons.count != 0 {
            barButtons.append(fixedSpace)
        }
        barButtons.append(camera)
        
        if #available(iOS 16, *) { // iOS 16 because PhotosPicker
            let photoButton = UIButton(type: .system)
            photoButton.setImage(UIImage(systemName: "photo"), for: .normal)
            photoButton.tintColor = UIColor(Themes.default.theme.accent)
            photoButton.addTarget(self, action: #selector(textView.photoPickerTapped), for: .touchUpInside)
            let photos = UIBarButtonItem(customView: photoButton)
            
            barButtons.append(fixedSpace)
            barButtons.append(photos)
            
            if kind != .shortVideos && kind != .picture {
                let videoButton = UIButton(type: .system)
                videoButton.setImage(UIImage(systemName: "video"), for: .normal)
                videoButton.tintColor = UIColor(Themes.default.theme.accent)
                videoButton.addTarget(self, action: #selector(textView.videoTapped), for: .touchUpInside)
                let videos = UIBarButtonItem(customView: videoButton)
                
                barButtons.append(fixedSpace)
                barButtons.append(videos)
            }
        }
        
        if kind != .shortVideos && kind != .picture {
            let gifButton = UIButton(type: .system)
            gifButton.setImage(UIImage(named: "GifButton"), for: .normal)
            gifButton.tintColor = UIColor(Themes.default.theme.accent)
        
            gifButton.imageView?.contentMode = .scaleAspectFit
            gifButton.sizeToFit()
            
            gifButton.addTarget(self, action: #selector(textView.gifsTapped), for: .touchUpInside)
            let gifs = UIBarButtonItem(customView: gifButton)
            
            barButtons.append(fixedSpace)
            barButtons.append(gifs)
        }
        
        
        let doneToolbar: UIToolbar = UIToolbar(frame: CGRect.init(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        doneToolbar.barStyle = .default
        
        barButtons.append(flexibleSpace) // last
        
        doneToolbar.setItems(barButtons, animated: false)
        
        uiView.inputAccessoryView = doneToolbar
    }
    
    public final class Coordinator: NSObject, UITextViewDelegate, PastedMediaDelegate {
        
        var isShowingVoiceRecorderButton = true
        var lastHasPrivateReplyAction: Bool?
        var lastPrivateReplyActive: Bool?
        var lastPrivateReplyLocked: Bool?
        
        func didPasteImage(_ image: UIImage) {
            if let gifData = image.gifData() {
                self.parent.pastedImages.append(PostedImageMeta(index: self.parent.pastedImages.count, data: gifData, type: .gif, uniqueId: UUID().uuidString))
            }
            else {
                guard let pngData = image.pngData() else { return }
                self.parent.pastedImages.append(PostedImageMeta(index: self.parent.pastedImages.count, data: pngData, type: .png, uniqueId: UUID().uuidString))
            }
        }
        
        func didPasteGif(_ data: Data) {
            self.parent.pastedImages.append(PostedImageMeta(index: self.parent.pastedImages.count, data: data, type: .gif, uniqueId: UUID().uuidString))
        }
        
        func didPastePlaceholderForGif(_ info: (UIImage, UUID)) {
            guard let pngData = info.0.pngData() else { return }
            self.parent.pastedImages.append(PostedImageMeta(index: self.parent.pastedImages.count, data: pngData, type: .png, uniqueId: info.1.uuidString, isGifPlaceholder: true))
        }
        
        func didFetchActualGif(_ info: (Data, UUID)) {
            // Replace placeholder first frame with actual gif
            self.parent.pastedImages = self.parent.pastedImages
                .map { meta in
                    if meta.uniqueId == info.1.uuidString {
                        return PostedImageMeta(index: meta.index, data: info.0, type: .gif, uniqueId: UUID().uuidString, isGifPlaceholder: false) // Give new id so view updates
                    }
                    return meta
                }
        }
        
        func didPasteVideo(_ video: URL) {
            self.parent.pastedVideos.append(PostedVideoMeta(index: self.parent.pastedVideos.count, videoURL: video))
        }
        
        func photoPickerTapped() {
            guard let photoTapped = self.parent.photoPickerTapped else { return }
            photoTapped()
        }
        
        func videoTapped() {
            guard let videoTapped = self.parent.videoPickerTapped else { return }
            videoTapped()
        }
        
        func gifsTapped() {
            guard let gifsTapped = self.parent.gifsTapped else { return }
            gifsTapped()
        }
        
        func cameraTapped() {
            guard let cameraTapped = self.parent.cameraTapped else { return }
            cameraTapped()
        }
        
        
        func nestsTapped() {
            guard let nestsTapped = self.parent.nestsTapped else { return }
            nestsTapped()
        }
        
        func voiceMessageTapped() {
            guard let voiceMessageTapped = self.parent.voiceMessageTapped else { return }
            voiceMessageTapped()
        }
        
        
        func privateReplyTapped() {
            guard let privateReplyTapped = self.parent.privateReplyTapped else { return }
            privateReplyTapped()
        }
        
        var parent: HighlightedTextEditor
        // Store offsets rather than UITextPosition objects. Replacing attributedText
        // rebuilds the text storage, which can invalidate UITextRange on newer iOS
        // versions and cause the insertion point to jump to the end.
        var selectedRange: NSRange?
        var updatingUIView = false
        private var applyingHighlighting = false
        private var pendingEditedRange: NSRange?
        private var lastHighlightedText: String?
        
        init(_ markdownEditorView: HighlightedTextEditor) {
            self.parent = markdownEditorView
            self.lastHasPrivateReplyAction = markdownEditorView.privateReplyTapped != nil
            self.lastPrivateReplyActive = markdownEditorView.isPrivateReplyActive
            self.lastPrivateReplyLocked = markdownEditorView.isPrivateReplyLocked
        }

        func applyHighlighting(to textView: UITextView, editedRange: NSRange? = nil) {
            guard !applyingHighlighting, textView.markedTextRange == nil else { return }
            let storage = textView.textStorage
            if editedRange == nil, lastHighlightedText == storage.string {
                return
            }

            let mentionRuns = textView.attributedText.nosturMentionRuns()
            let targetRange = highlightingRange(
                in: storage.string as NSString,
                editedRange: editedRange
            )
            guard targetRange.length > 0 else {
                lastHighlightedText = storage.string
                return
            }
            let targetText = (storage.string as NSString).substring(with: targetRange)
            let highlightedText = HighlightedTextEditor.getHighlightedText(
                text: targetText,
                highlightRules: parent.highlightRules
            )
            guard highlightedText.string == targetText else { return }

            applyingHighlighting = true
            defer { applyingHighlighting = false }
            storage.beginEditing()
            highlightedText.enumerateAttributes(
                in: NSRange(location: 0, length: highlightedText.length)
            ) { attributes, range, _ in
                storage.setAttributes(
                    attributes,
                    range: NSRange(
                        location: targetRange.location + range.location,
                        length: range.length
                    )
                )
            }
            storage.endEditing()
            restoreMentionRuns(mentionRuns, in: textView)
            lastHighlightedText = storage.string
        }

        func didHighlightAllText(_ text: String) {
            lastHighlightedText = text
        }

        private func highlightingRange(
            in text: NSString,
            editedRange: NSRange?
        ) -> NSRange {
            guard let editedRange, text.length > 0 else {
                return NSRange(location: 0, length: text.length)
            }

            let location = min(editedRange.location, text.length)
            let start = max(0, location - 1)
            let proposedEnd = location + max(editedRange.length, 1) + 1
            let end = min(text.length, proposedEnd)
            return text.paragraphRange(
                for: NSRange(location: start, length: max(0, end - start))
            )
        }

        func restoreMentionRuns(_ runs: [NosturMentionAttributeRun], in textView: UITextView) {
            let storage = textView.textStorage
            for run in runs {
                guard NSMaxRange(run.range) <= storage.length,
                      storage.attributedSubstring(from: run.range).string == run.text else { continue }

                storage.addAttribute(.nosturMentionPubkey, value: run.pubkey, range: run.range)
                storage.addAttribute(
                    .foregroundColor,
                    value: UIColor(Themes.default.theme.accent),
                    range: run.range
                )
                storage.addAttribute(
                    .font,
                    value: UIFont.nosturBody().with(.traitBold),
                    range: run.range
                )
            }
        }

        public func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            pendingEditedRange = NSRange(
                location: range.location,
                length: (text as NSString).length
            )

            // Editing inside an attributed mention turns it back into ordinary
            // text, preventing a changed label from retaining the old pubkey.
            let storage = textView.textStorage
            let inspectionRange: NSRange
            if range.length > 0 {
                inspectionRange = range
            } else if range.location < storage.length {
                inspectionRange = NSRange(location: range.location, length: 1)
            } else {
                return true
            }

            var mentionRanges: [NSRange] = []
            for location in inspectionRange.location..<NSMaxRange(inspectionRange) {
                var effectiveRange = NSRange()
                if storage.attribute(
                    .nosturMentionPubkey,
                    at: location,
                    effectiveRange: &effectiveRange
                ) != nil,
                   !mentionRanges.contains(effectiveRange) {
                    mentionRanges.append(effectiveRange)
                }
            }
            for mentionRange in mentionRanges {
                storage.removeAttribute(.nosturMentionPubkey, range: mentionRange)
            }
            return true
        }
        
        
        public func textViewDidChange(_ textView: UITextView) {
            guard !applyingHighlighting else { return }
            textView.backgroundColor = textView.text.isEmpty && textView.markedTextRange == nil ? UIColor.clear : UIColor(Themes.default.theme.listBackground)
            
            // For Multistage Text Input
            guard textView.markedTextRange == nil else { return }

            let editedRange = pendingEditedRange
            pendingEditedRange = nil
            applyHighlighting(to: textView, editedRange: editedRange)
            parent.text = textView.text
            selectedRange = textView.selectedRange
        }
        
        public func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updatingUIView else { return }
            selectedRange = textView.selectedRange
        }
    }
}

public extension HighlightedTextEditor {
    func introspect(callback: @escaping IntrospectCallback) -> Self {
        var new = self
        new.introspect = callback
        return new
    }
}
#endif
