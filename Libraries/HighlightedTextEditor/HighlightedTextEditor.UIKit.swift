#if os(iOS)
//
//  HighlightedTextEditor.UIKit.swift
//
//
//  Created by Kyle Nazario on 5/26/21.
//  Modified by Fabian Lachman 2023

import SwiftUI
import UIKit

public typealias PhotoPickerTappedCallback = () -> Void
public typealias VideoPickerTappedCallback = () -> Void
public typealias GifsTappedCallback = () -> Void
public typealias CameraTappedCallback = () -> Void
public typealias NestsTappedCallback = () -> Void

protocol PastedMediaDelegate: UITextViewDelegate {
    func didPasteImage(_ image: UIImage)
    func didPasteVideo(_ video: URL)
    func photoPickerTapped()
    func videoTapped()
    func gifsTapped()
    func cameraTapped()
    func nestsTapped()
}

class NosturTextView: UITextView {
    var pastedMediaDelegate: PastedMediaDelegate?

    override var delegate: UITextViewDelegate? {
        get { pastedMediaDelegate }
        set { pastedMediaDelegate = newValue as? PastedMediaDelegate }
    }

    // This gets called when user presses menu "Paste" option
    override func paste(_ sender: Any?) {
        if let image = UIPasteboard.general.image {
            pastedMediaDelegate?.didPasteImage(image)
        } else {
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
    
    
}

public struct HighlightedTextEditor: UIViewRepresentable, HighlightingTextEditor {
    
    public struct Internals {
        public let textView: SystemTextView
        public let scrollView: SystemScrollView?
    }
    
    @Binding var text: String
    
    @Binding var pastedImages: [PostedImageMeta]
    @Binding var pastedVideos: [PostedVideoMeta]
    
    var shouldBecomeFirstResponder: Bool
    
    let textView = NosturTextView()
    let highlightRules: [HighlightRule]
    var photoPickerTapped: PhotoPickerTappedCallback?
    var videoPickerTapped: VideoPickerTappedCallback?
    var gifsTapped: GifsTappedCallback?
    var cameraTapped: CameraTappedCallback?
    var nestsTapped: NestsTappedCallback?
    var kind: NEventKind?
    
    private(set) var onEditingChanged: OnEditingChangedCallback?
    private(set) var onCommit: OnCommitCallback?
    private(set) var introspect: IntrospectCallback?
    
    public init(
        text: Binding<String>,
        kind: NEventKind? = nil,
        pastedImages: Binding<[PostedImageMeta]>,
        pastedVideos: Binding<[PostedVideoMeta]>,
        shouldBecomeFirstResponder: Bool,
        highlightRules: [HighlightRule],
        photoPickerTapped: PhotoPickerTappedCallback? = nil,
        videoPickerTapped: VideoPickerTappedCallback? = nil,
        gifsTapped: GifsTappedCallback? = nil,
        cameraTapped: CameraTappedCallback? = nil,
        nestsTapped: NestsTappedCallback? = nil
    ) {
        _text = text
        _pastedImages = pastedImages
        _pastedVideos = pastedVideos
        self.shouldBecomeFirstResponder = shouldBecomeFirstResponder
        self.highlightRules = highlightRules
        self.photoPickerTapped = photoPickerTapped
        self.videoPickerTapped = videoPickerTapped
        self.gifsTapped = gifsTapped
        self.cameraTapped = cameraTapped
        self.nestsTapped = nestsTapped
        self.kind = kind
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIView(context: Context) -> UITextView {
//        _ = textView.layoutManager // force an UITextView to fallback to Text Kit 1 - Maybe fixes crashes on iOS17 beta
        
        if #available(iOS 17.0, *) {
            // iOS 17 inline prediction and HighlightedTextEditor don't mix well, spits out double text
            // so disable for now
            textView.inlinePredictionType = .no
        }
        
        textView.smartInsertDeleteType = .no
        textView.isScrollEnabled = true
        textView.backgroundColor = UIColor.clear
        textView.delegate = context.coordinator
        textView.pastedMediaDelegate = context.coordinator
        
        let doneToolbar: UIToolbar = UIToolbar(frame: CGRect.init(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        doneToolbar.barStyle = .default
        
        let nestsButton = UIButton(type: .system)
        nestsButton.setImage(UIImage(systemName: "mic"), for: .normal)
        nestsButton.tintColor = UIColor(Themes.default.theme.accent)
        nestsButton.addTarget(self, action: #selector(textView.nestsTapped), for: .touchUpInside)
        let nests = UIBarButtonItem(customView: nestsButton)
        
        let cameraButton = UIButton(type: .system)
        cameraButton.setImage(UIImage(systemName: "camera"), for: .normal)
        cameraButton.tintColor = UIColor(Themes.default.theme.accent)
        cameraButton.addTarget(self, action: #selector(textView.cameraTapped), for: .touchUpInside)
        let camera = UIBarButtonItem(customView: cameraButton)
    
        let gifButton = UIButton(type: .system)
        gifButton.setImage(UIImage(named: "GifButton"), for: .normal)
        gifButton.tintColor = UIColor(Themes.default.theme.accent)
    
        gifButton.imageView?.contentMode = .scaleAspectFit
        gifButton.sizeToFit()
        
        gifButton.addTarget(self, action: #selector(textView.gifsTapped), for: .touchUpInside)
        let gifs = UIBarButtonItem(customView: gifButton)

        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        let fixedSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpace.width = 9
        
        let photoButton = UIButton(type: .system)
        photoButton.setImage(UIImage(systemName: "photo"), for: .normal)
        photoButton.tintColor = UIColor(Themes.default.theme.accent)
        photoButton.addTarget(self, action: #selector(textView.photoPickerTapped), for: .touchUpInside)
        let photos = UIBarButtonItem(customView: photoButton)
    
        if kind == .picture, #available(iOS 16, *) {
            doneToolbar.setItems([camera, fixedSpace, photos, flexibleSpace], animated: false)
        }
        else if #available(iOS 16, *) {
            
            let videoButton = UIButton(type: .system)
            videoButton.setImage(UIImage(systemName: "video"), for: .normal)
            videoButton.tintColor = UIColor(Themes.default.theme.accent)
            videoButton.addTarget(self, action: #selector(textView.videoTapped), for: .touchUpInside)
            let videos = UIBarButtonItem(customView: videoButton)
            
            doneToolbar.setItems([nests, fixedSpace, camera, fixedSpace, photos, fixedSpace, videos, gifs, flexibleSpace], animated: false)
        }
        else {
            doneToolbar.setItems([nests, fixedSpace, camera, fixedSpace, gifs, flexibleSpace], animated: false)
        }
      

        textView.inputAccessoryView = doneToolbar
//        textView.keyboardType = .twitter
        textView.font = UIFont.systemFont(ofSize: UIFont.systemFontSize + 4.0)
        
        updateTextViewModifiers(textView)
        if (shouldBecomeFirstResponder) {
            textView.becomeFirstResponder()
        }
        return textView
    }
    
    public func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.isScrollEnabled = false
        context.coordinator.updatingUIView = true
        
        uiView.backgroundColor = text.isEmpty ? UIColor.clear : UIColor(Themes.default.theme.background)
        
        let highlightedText = HighlightedTextEditor.getHighlightedText(
            text: text,
            highlightRules: highlightRules
        )
        
        if let range = uiView.markedTextNSRange {
            uiView.setAttributedMarkedText(highlightedText, selectedRange: range)
        } else {
            uiView.attributedText = highlightedText
        }
        updateTextViewModifiers(uiView)
        runIntrospect(uiView)
        uiView.isScrollEnabled = true
        uiView.selectedTextRange = context.coordinator.selectedTextRange
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
    
    public final class Coordinator: NSObject, UITextViewDelegate, PastedMediaDelegate {
        
        func didPasteImage(_ image: UIImage) {
            self.parent.pastedImages.append(PostedImageMeta(index: self.parent.pastedImages.count, imageData: image, type: .jpeg, uniqueId: UUID().uuidString))
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
        
        var parent: HighlightedTextEditor
        var selectedTextRange: UITextRange?
        var updatingUIView = false
        
        init(_ markdownEditorView: HighlightedTextEditor) {
            self.parent = markdownEditorView
        }
        
        
        public func textViewDidChange(_ textView: UITextView) {
            textView.backgroundColor = textView.text.isEmpty && textView.markedTextRange == nil ? UIColor.clear : UIColor(Themes.default.theme.background)
            
            // For Multistage Text Input
            guard textView.markedTextRange == nil else { return }

            parent.text = textView.text
            selectedTextRange = textView.selectedTextRange
        }
        
        public func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updatingUIView else { return }
            selectedTextRange = textView.selectedTextRange
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
