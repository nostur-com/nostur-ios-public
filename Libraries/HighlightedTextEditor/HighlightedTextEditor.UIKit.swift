#if os(iOS)
//
//  HighlightedTextEditor.UIKit.swift
//
//
//  Created by Kyle Nazario on 5/26/21.
//  Modified by Fabian Lachman 2023

import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
public typealias PollTappedCallback = () -> Void

protocol PastedMediaDelegate: UITextViewDelegate {
    func didPasteImageData(_ data: Data, type: PostedImageMeta.ImageType, remoteGIF: URL?)
    func didFetchActualGif(_ info: (Data, UUID))

    func photoPickerTapped()
    func videoTapped()
    func gifsTapped()
    func cameraTapped()
    func nestsTapped()
    func voiceMessageTapped()
    func privateReplyTapped()
    func pollTapped()
}

class NosturTextView: UITextView {
    var onBeginComposition: (() -> Void)?
    var onProgrammaticEdit: ((UITextView, NSRange, Int) -> Void)?
    private var pastedMediaDelegate: PastedMediaDelegate? { delegate as? PastedMediaDelegate }

    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        if markedTextRange == nil, markedText != nil {
            onBeginComposition?()
        }
        super.setMarkedText(markedText, selectedRange: selectedRange)
    }

    override func unmarkText() {
        let hadMarkedText = markedTextRange != nil
        super.unmarkText()
        if hadMarkedText, markedTextRange == nil {
            delegate?.textViewDidChange?(self)
        }
    }

    private var mediaPasteTask: Task<Void, Never>?

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        if pastedMediaDelegate != nil, pasteboard.hasImages {
            let remoteGIF = pasteboard.hasURLs ? pasteboard.url : nil
            if pasteImage(from: pasteboard.itemProviders, remoteGIF: remoteGIF) { return }
        }
        super.paste(sender)
    }

    override func paste(itemProviders: [NSItemProvider]) {
        if pasteImage(from: itemProviders, remoteGIF: nil) { return }
        super.paste(itemProviders: itemProviders)
    }

    private func pasteImage(from providers: [NSItemProvider], remoteGIF: URL?) -> Bool {
        guard pastedMediaDelegate != nil,
              let provider = providers.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.gif.identifier) || $0.canLoadObject(ofClass: UIImage.self)
              }) else { return false }
        let previousPaste = mediaPasteTask
        mediaPasteTask = Task { @MainActor [weak self] in
            await previousPaste?.value
            guard self?.pastedMediaDelegate != nil else { return }
            let gif: Data? = await withCheckedContinuation { continuation in
                if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.gif.identifier) { data, _ in
                        continuation.resume(returning: data)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
            if let gif {
                self?.pastedMediaDelegate?.didPasteImageData(gif, type: .gif, remoteGIF: nil)
                return
            }
            guard provider.canLoadObject(ofClass: UIImage.self) else { return }
            let imageData: Data? = await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    continuation.resume(returning: (image as? UIImage)?.pngData())
                }
            }
            if let imageData {
                let gifURL = remoteGIF.flatMap { url in
                    ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.pathExtension.lowercased() == "gif"
                        ? url : nil
                }
                self?.pastedMediaDelegate?.didPasteImageData(imageData, type: .png, remoteGIF: gifURL)
            }
        }
        return true
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) && UIPasteboard.general.hasImages {
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

    @objc func pollTapped() {
        pastedMediaDelegate?.pollTapped()
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
        undoActionName: String? = nil,
        restoringSelection: NSRange? = nil
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
        selectedRange = restoringSelection ?? insertionPoint

        if let undoActionName, let undoManager {
            let undoRange = NSRange(location: range.location, length: replacement.length)
            undoManager.registerUndo(withTarget: self) { textView in
                _ = textView.replaceTextStorageCharacters(
                    in: undoRange,
                    with: replacedText,
                    undoActionName: undoActionName,
                    restoringSelection: selectionBeforeReplacement
                )
            }
            undoManager.setActionName(undoActionName)
        }
        (self as? NosturTextView)?.onProgrammaticEdit?(self, range, replacement.length)
        return insertionPoint
    }
}

public struct HighlightedTextEditor: UIViewRepresentable, HighlightingTextEditor {
    
    public struct Internals {
        public let textView: SystemTextView
        public let scrollView: SystemScrollView?
    }
    
    let initialDocument: ComposerDraft
    var onEditorChange: ((UITextView) -> Void)?
    var onSelectionChange: (() -> Void)?
    var onBeginComposition: (() -> Void)?
    var onEditorDetach: ((UITextView) -> Void)?
    
    @Binding var pastedImages: [PostedImageMeta]
    @Binding var pastedVideos: [PostedVideoMeta]
    @Binding var showVoiceRecorderButton: Bool
    
    var shouldBecomeFirstResponder: Bool
    
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
    var pollTapped: PollTappedCallback?
    var isPollActive: Bool
    var kind: NEventKind?
    
    private(set) var onEditingChanged: OnEditingChangedCallback?
    private(set) var onCommit: OnCommitCallback?
    private(set) var introspect: IntrospectCallback?
    
    init(
        initialDocument: ComposerDraft,
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
        isPrivateReplyLocked: Bool = false,
        pollTapped: PollTappedCallback? = nil,
        isPollActive: Bool = false
    ) {
        self.initialDocument = initialDocument
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
        self.pollTapped = pollTapped
        self.isPollActive = isPollActive
        self.kind = kind
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIView(context: Context) -> UITextView {
        let textView = NosturTextView()
        
        if #available(iOS 17.0, *) {
            // Local edits no longer replace the full attributed string, so the
            // system can safely manage inline prediction state.
            textView.inlinePredictionType = .default
        }
        
        textView.smartInsertDeleteType = .no
        textView.isScrollEnabled = true
        textView.backgroundColor = UIColor.clear
        textView.delegate = context.coordinator
        textView.onBeginComposition = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onBeginComposition?()
        }
        textView.onProgrammaticEdit = { [weak coordinator = context.coordinator] view, range, length in
            coordinator?.commitEdit(in: view, replacing: range, withLength: length)
        }
        if kind != .shortVideos {
            if #available(iOS 26.0, *) {
                makeToolbar26(textView)
            }
            else {
                makeToolbar(textView)
            }
        }
        textView.font = context.coordinator.baseFont
        textView.adjustsFontForContentSizeCategory = true
        
        context.coordinator.installInitialText(in: textView)
        updateTextViewModifiers(textView)
        runIntrospect(textView)
        if (shouldBecomeFirstResponder) {
            textView.becomeFirstResponder()
        }
        return textView
    }
    
    public func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        
        // Only turn off, never turn on
        if !showVoiceRecorderButton && context.coordinator.isShowingVoiceRecorderButton {
            if #available(iOS 26.0, *) {
                makeToolbar26(uiView)
            }
            else {
                makeToolbar(uiView)
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
        let didPollChange = context.coordinator.lastIsPollActive != isPollActive
            || context.coordinator.lastHasPollAction != (pollTapped != nil)

        if didPrivateReplyActionChange || didPrivateReplyStateChange || didPollChange {
            if #available(iOS 26.0, *) {
                makeToolbar26(uiView)
            }
            else {
                makeToolbar(uiView)
            }
            context.coordinator.lastHasPrivateReplyAction = hasPrivateReplyAction
            context.coordinator.lastPrivateReplyActive = isPrivateReplyActive
            context.coordinator.lastPrivateReplyLocked = isPrivateReplyLocked
            context.coordinator.lastIsPollActive = isPollActive
            context.coordinator.lastHasPollAction = pollTapped != nil

            // Refresh toolbar button icon and enabled state when private reply availability changes.
            uiView.reloadInputViews()
        }
        
        context.coordinator.updateBaseFont(of: uiView)
        context.coordinator.updateBackground(of: uiView)
    }

    public static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        coordinator.parent.onEditorDetach?(uiView)
        uiView.delegate = nil
    }

    func onEditorEvents(
        onChange: @escaping (UITextView) -> Void,
        onSelectionChange: @escaping () -> Void,
        onBeginComposition: @escaping () -> Void,
        onDetach: @escaping (UITextView) -> Void
    ) -> Self {
        var editor = self
        editor.onEditorChange = onChange
        editor.onSelectionChange = onSelectionChange
        editor.onBeginComposition = onBeginComposition
        editor.onEditorDetach = onDetach
        return editor
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
    private func makeToolbar26(_ uiView: UITextView) {
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        flexibleSpace.hidesSharedBackground = false
        
        var barButtons: [UIBarButtonItem] = []
        
        if privateReplyTapped != nil {
            let privateReplyButton = UIButton(type: .system)
            privateReplyButton.setImage(UIImage(systemName: isPrivateReplyActive ? "lock.fill" : "lock.open"), for: .normal)
            privateReplyButton.tintColor = UIColor(Themes.default.theme.accent)
            privateReplyButton.isEnabled = !isPrivateReplyLocked
            privateReplyButton.addTarget(uiView, action: #selector(NosturTextView.privateReplyTapped), for: .touchUpInside)
            let privateReply = UIBarButtonItem(customView: privateReplyButton)
            barButtons.append(privateReply)
        }

        if let pollItem = pollBarButton(for: uiView) {
            barButtons.append(pollItem)
        }

        if isPollActive {
            let doneToolbar: UIToolbar = UIToolbar(frame: CGRect.init(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
            doneToolbar.barStyle = .default
            barButtons.append(flexibleSpace)
            doneToolbar.setItems(barButtons, animated: false)
            uiView.inputAccessoryView = doneToolbar
            return
        }
        
        if showVoiceRecorderButton {
            let voiceRecordingButton = UIButton(type: .system)
            voiceRecordingButton.setImage(UIImage(systemName: "mic"), for: .normal)
            voiceRecordingButton.tintColor = UIColor(Themes.default.theme.accent)
            voiceRecordingButton.addTarget(uiView, action: #selector(NosturTextView.voiceMessageTapped), for: .touchUpInside)
            let voiceRecording = UIBarButtonItem(customView: voiceRecordingButton)
            barButtons.append(voiceRecording)
        }
        
        let cameraButton = UIButton(type: .system)
        cameraButton.setImage(UIImage(systemName: "camera"), for: .normal)
        cameraButton.tintColor = UIColor(Themes.default.theme.accent)
        cameraButton.addTarget(uiView, action: #selector(NosturTextView.cameraTapped), for: .touchUpInside)
        let camera = UIBarButtonItem(customView: cameraButton)
        barButtons.append(camera)
        
        let photoButton = UIButton(type: .system)
        photoButton.setImage(UIImage(systemName: "photo"), for: .normal)
        photoButton.tintColor = UIColor(Themes.default.theme.accent)
        photoButton.addTarget(uiView, action: #selector(NosturTextView.photoPickerTapped), for: .touchUpInside)
        let photos = UIBarButtonItem(customView: photoButton)
        barButtons.append(photos)
        
        if kind != .shortVideos && kind != .picture {
            let videoButton = UIButton(type: .system)
            videoButton.setImage(UIImage(systemName: "video"), for: .normal)
            videoButton.tintColor = UIColor(Themes.default.theme.accent)
            videoButton.addTarget(uiView, action: #selector(NosturTextView.videoTapped), for: .touchUpInside)
            let videos = UIBarButtonItem(customView: videoButton)
            barButtons.append(videos)
            
            
            let gifButton = UIButton(type: .system)
            gifButton.setImage(UIImage(named: "GifButton"), for: .normal)
            gifButton.tintColor = UIColor(Themes.default.theme.accent)
        
            gifButton.imageView?.contentMode = .scaleAspectFit
            gifButton.sizeToFit()
            
            gifButton.addTarget(uiView, action: #selector(NosturTextView.gifsTapped), for: .touchUpInside)
            let gifs = UIBarButtonItem(customView: gifButton)
            barButtons.append(gifs)
        }
        
        
        let doneToolbar: UIToolbar = UIToolbar(frame: CGRect.init(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        doneToolbar.barStyle = .default
        
        barButtons.append(flexibleSpace) // last
        
        doneToolbar.setItems(barButtons, animated: false)
        
        uiView.inputAccessoryView = doneToolbar
    }
    
    private func makeToolbar(_ uiView: UITextView) {
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        let fixedSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpace.width = 9
        
        var barButtons: [UIBarButtonItem] = []
        
        if privateReplyTapped != nil {
            let privateReplyButton = UIButton(type: .system)
            privateReplyButton.setImage(UIImage(systemName: isPrivateReplyActive ? "lock.fill" : "lock.open"), for: .normal)
            privateReplyButton.tintColor = UIColor(Themes.default.theme.accent)
            privateReplyButton.isEnabled = !isPrivateReplyLocked
            privateReplyButton.addTarget(uiView, action: #selector(NosturTextView.privateReplyTapped), for: .touchUpInside)
            let privateReply = UIBarButtonItem(customView: privateReplyButton)
            barButtons.append(privateReply)
        }

        if let pollItem = pollBarButton(for: uiView) {
            if barButtons.count != 0 {
                barButtons.append(fixedSpace)
            }
            barButtons.append(pollItem)
        }

        if isPollActive {
            let doneToolbar: UIToolbar = UIToolbar(frame: CGRect.init(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
            doneToolbar.barStyle = .default
            barButtons.append(flexibleSpace)
            doneToolbar.setItems(barButtons, animated: false)
            uiView.inputAccessoryView = doneToolbar
            return
        }
        
        if showVoiceRecorderButton {
            let voiceRecordingButton = UIButton(type: .system)
            voiceRecordingButton.setImage(UIImage(systemName: "mic"), for: .normal)
            voiceRecordingButton.tintColor = UIColor(Themes.default.theme.accent)
            voiceRecordingButton.addTarget(uiView, action: #selector(NosturTextView.voiceMessageTapped), for: .touchUpInside)
            let voiceRecording = UIBarButtonItem(customView: voiceRecordingButton)
            
            if barButtons.count != 0 {
                barButtons.append(fixedSpace)
            }
            barButtons.append(voiceRecording)
        }
        
        let cameraButton = UIButton(type: .system)
        cameraButton.setImage(UIImage(systemName: "camera"), for: .normal)
        cameraButton.tintColor = UIColor(Themes.default.theme.accent)
        cameraButton.addTarget(uiView, action: #selector(NosturTextView.cameraTapped), for: .touchUpInside)
        let camera = UIBarButtonItem(customView: cameraButton)
        
        if barButtons.count != 0 {
            barButtons.append(fixedSpace)
        }
        barButtons.append(camera)
        
        if #available(iOS 16, *) { // iOS 16 because PhotosPicker
            let photoButton = UIButton(type: .system)
            photoButton.setImage(UIImage(systemName: "photo"), for: .normal)
            photoButton.tintColor = UIColor(Themes.default.theme.accent)
            photoButton.addTarget(uiView, action: #selector(NosturTextView.photoPickerTapped), for: .touchUpInside)
            let photos = UIBarButtonItem(customView: photoButton)
            
            barButtons.append(fixedSpace)
            barButtons.append(photos)
            
            if kind != .shortVideos && kind != .picture {
                let videoButton = UIButton(type: .system)
                videoButton.setImage(UIImage(systemName: "video"), for: .normal)
                videoButton.tintColor = UIColor(Themes.default.theme.accent)
                videoButton.addTarget(uiView, action: #selector(NosturTextView.videoTapped), for: .touchUpInside)
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
            
            gifButton.addTarget(uiView, action: #selector(NosturTextView.gifsTapped), for: .touchUpInside)
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

    private func pollBarButton(for uiView: UITextView) -> UIBarButtonItem? {
        guard pollTapped != nil else { return nil }
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: isPollActive ? "chart.bar.fill" : "chart.bar.xaxis"), for: .normal)
        button.tintColor = UIColor(Themes.default.theme.accent)
        button.accessibilityLabel = isPollActive ? "Remove poll" : "Poll"
        button.addTarget(uiView, action: #selector(NosturTextView.pollTapped), for: .touchUpInside)
        return UIBarButtonItem(customView: button)
    }
    
    public final class Coordinator: NSObject, UITextViewDelegate, PastedMediaDelegate {
        
        var isShowingVoiceRecorderButton = true
        var lastHasPrivateReplyAction: Bool?
        var lastPrivateReplyActive: Bool?
        var lastPrivateReplyLocked: Bool?
        var lastIsPollActive = false
        var lastHasPollAction = false
        
        func didPasteImageData(_ data: Data, type: PostedImageMeta.ImageType, remoteGIF: URL?) {
            let id = UUID()
            parent.pastedImages.append(PostedImageMeta(
                index: parent.pastedImages.count, data: data, type: type,
                uniqueId: id.uuidString, isGifPlaceholder: remoteGIF != nil
            ))
            guard let remoteGIF else { return }
            URLSession.shared.dataTask(with: remoteGIF) { [weak self] data, _, _ in
                guard let data else { return }
                DispatchQueue.main.async { self?.didFetchActualGif((data, id)) }
            }.resume()
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

        func pollTapped() {
            guard let pollTapped = self.parent.pollTapped else { return }
            pollTapped()
        }
        
        var parent: HighlightedTextEditor
        private(set) var baseFont = UIFont.nosturBody()
        private var applyingHighlighting = false
        private var pendingEdit: (range: NSRange, insertedLength: Int, oldLength: Int, mentions: [NSRange])?
        private var dirtyHighlightRange: NSRange?
        private var highlightWork: DispatchWorkItem?
        private var highlightRevision = 0
        
        init(_ markdownEditorView: HighlightedTextEditor) {
            self.parent = markdownEditorView
            self.lastHasPrivateReplyAction = markdownEditorView.privateReplyTapped != nil
            self.lastPrivateReplyActive = markdownEditorView.isPrivateReplyActive
            self.lastPrivateReplyLocked = markdownEditorView.isPrivateReplyLocked
            self.lastIsPollActive = markdownEditorView.isPollActive
            self.lastHasPollAction = markdownEditorView.pollTapped != nil
        }

        func applyHighlighting(to textView: UITextView, editedRange: NSRange? = nil) {
            guard !applyingHighlighting, textView.markedTextRange == nil else { return }
            let storage = textView.textStorage
            let targetRange = highlightingRange(
                in: storage.string as NSString,
                editedRange: editedRange
            )
            guard targetRange.length > 0 else { return }
            let targetText = (storage.string as NSString).substring(with: targetRange)
            applyHighlighting(to: textView, in: targetRange, text: targetText)
        }

        private func applyHighlighting(to textView: UITextView, in targetRange: NSRange, text targetText: String, matchedRanges: [[NSRange]]? = nil) {
            let storage = textView.textStorage
            let highlightedText = HighlightedTextEditor.getHighlightedText(
                text: targetText,
                highlightRules: parent.highlightRules,
                matchedRanges: matchedRanges
            )
            guard highlightedText.string == targetText else { return }

            applyingHighlighting = true
            defer { applyingHighlighting = false }
            let accent = UIColor(Themes.default.theme.accent)
            let mentionFont = baseFont.with(.traitBold)
            storage.enumerateAttribute(.nosturMentionPubkey, in: targetRange) { value, range, _ in
                guard let pubkey = value as? String else { return }
                highlightedText.addAttributes([
                    .nosturMentionPubkey: pubkey,
                    .foregroundColor: accent,
                    .font: mentionFont
                ], range: NSRange(location: range.location - targetRange.location, length: range.length))
            }
            storage.beginEditing()
            highlightedText.enumerateAttributes(
                in: NSRange(location: 0, length: highlightedText.length)
            ) { attributes, range, _ in
                let storageRange = NSRange(location: targetRange.location + range.location, length: range.length)
                var changedRanges: [NSRange] = []
                storage.enumerateAttributes(in: storageRange) { existing, subrange, _ in
                    if !NSDictionary(dictionary: existing).isEqual(to: attributes) {
                        changedRanges.append(subrange)
                    }
                }
                for changedRange in changedRanges {
                    storage.setAttributes(attributes, range: changedRange)
                }
            }
            storage.endEditing()

        }

        func installInitialText(in textView: UITextView) {
            let document = parent.initialDocument
            let text = NSMutableAttributedString(attributedString: document.semanticText)
            text.addAttributes([.font: baseFont, .foregroundColor: UIColor.label], range: NSRange(location: 0, length: text.length))
            let storage = textView.textStorage
            storage.setAttributedString(text)
            if text.length > 0 {
                textView.selectedRange = NSRange(location: text.length, length: 0)
            }
            if storage.length > 0 {
                dirtyHighlightRange = NSRange(location: 0, length: storage.length)
                scheduleHighlighting(in: textView)
            }
        }

        func updateBaseFont(of textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            let font = UIFont.nosturBody()
            guard font != baseFont else { return }
            baseFont = font
            textView.font = font
            dirtyHighlightRange = NSRange(location: 0, length: textView.textStorage.length)
            scheduleHighlighting(in: textView)
        }

        func updateBackground(of textView: UITextView) {
            let backgroundColor: UIColor = textView.text.isEmpty && textView.markedTextRange == nil
                ? .clear : UIColor(Themes.default.theme.listBackground)
            if textView.backgroundColor != backgroundColor {
                textView.backgroundColor = backgroundColor
            }
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

        public func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            let storage = textView.textStorage
            let length = storage.length
            guard range.location <= length, range.length <= length - range.location else { return true }
            let inspectionStart = max(0, range.location - 1)
            let inspectionEnd = min(length, NSMaxRange(range) + 1)
            let inspection = NSRange(location: inspectionStart, length: inspectionEnd - inspectionStart)
            let fullRange = NSRange(location: 0, length: length)
            var mentions: [NSRange] = []
            storage.enumerateAttribute(.nosturMentionPubkey, in: inspection) { pubkey, run, _ in
                guard pubkey != nil else { return }
                var mention = NSRange()
                _ = storage.attribute(.nosturMentionPubkey, at: run.location, longestEffectiveRange: &mention, in: fullRange)
                let touchesInterior = range.length == 0
                    ? range.location > mention.location && range.location < NSMaxRange(mention)
                    : NSIntersectionRange(range, mention).length > 0
                if touchesInterior { mentions.append(mention) }
            }
            pendingEdit = (range, text.utf16.count, length, mentions)
            return true
        }

        public func textViewDidChange(_ textView: UITextView) {
            guard !applyingHighlighting else { return }
            if textView.markedTextRange != nil {
                updateBackground(of: textView)
                return
            }
            let storage = textView.textStorage
            let edit = pendingEdit
            pendingEdit = nil
            if let edit, storage.length == edit.oldLength - edit.range.length + edit.insertedLength {
                // Plain typing at a token boundary can inherit the token's attributes.
                let inserted = NSRange(location: edit.range.location, length: edit.insertedLength)
                var invalidated = inserted
                if !edit.mentions.isEmpty {
                    for mention in edit.mentions {
                        invalidated = NSUnionRange(invalidated, adjustedRange(mention, replacing: edit.range, withLength: edit.insertedLength))
                    }
                }
                if invalidated.length > 0, !edit.mentions.isEmpty || (edit.range.length == 0 && inserted.length > 0) {
                    applyingHighlighting = true
                    storage.removeAttribute(.nosturMentionPubkey, range: invalidated)
                    applyingHighlighting = false
                }
                commitEdit(in: textView, replacing: edit.range, withLength: edit.insertedLength)
            } else {
                dirtyHighlightRange = NSRange(location: 0, length: storage.length)
                reportEdit(in: textView)
            }
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            guard !applyingHighlighting else { return }
            parent.onSelectionChange?()
        }

        func commitEdit(in textView: UITextView, replacing range: NSRange, withLength length: Int) {
            let inserted = NSRange(location: range.location, length: length)
            if let dirty = dirtyHighlightRange {
                dirtyHighlightRange = NSUnionRange(adjustedRange(dirty, replacing: range, withLength: length), inserted)
            } else {
                dirtyHighlightRange = inserted
            }
            reportEdit(in: textView)
        }

        private func adjustedRange(_ oldRange: NSRange, replacing edit: NSRange, withLength length: Int) -> NSRange {
            let delta = length - edit.length
            let start = oldRange.location < edit.location ? oldRange.location : max(edit.location, oldRange.location + delta)
            let end = NSMaxRange(oldRange) <= edit.location ? NSMaxRange(oldRange) : max(edit.location + length, NSMaxRange(oldRange) + delta)
            return NSRange(location: start, length: max(0, end - start))
        }

        private func reportEdit(in textView: UITextView) {
            updateBackground(of: textView)
            parent.onEditorChange?(textView)
            scheduleHighlighting(in: textView)
        }

        private func scheduleHighlighting(in textView: UITextView) {
            highlightRevision += 1
            let revision = highlightRevision
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView, textView.markedTextRange == nil,
                      let dirty = self.dirtyHighlightRange else { return }
                let text = textView.textStorage.string as NSString
                let range = self.highlightingRange(in: text, editedRange: dirty)
                guard range.length > 8_192 else {
                    self.dirtyHighlightRange = nil
                    self.applyHighlighting(to: textView, editedRange: dirty)
                    return
                }

                let source = text.substring(with: range)
                let patterns = self.parent.highlightRules.map(\.pattern)
                DispatchQueue.global(qos: .userInitiated).async { [weak self, weak textView] in
                    let sourceRange = NSRange(location: 0, length: source.utf16.count)
                    let matches = patterns.map { $0.matches(in: source, range: sourceRange).map(\.range) }
                    DispatchQueue.main.async {
                        guard let self, let textView, self.highlightRevision == revision, textView.markedTextRange == nil else { return }
                        self.dirtyHighlightRange = nil
                        self.applyHighlighting(to: textView, in: range, text: source, matchedRanges: matches)
                    }
                }
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035, execute: work)
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
