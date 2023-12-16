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
public typealias GifsTappedCallback = () -> Void
public typealias CameraTappedCallback = () -> Void

protocol PastedImagesDelegate: UITextViewDelegate {
    func didPasteImage(_ image:UIImage)
    func photoPickerTapped()
    func gifsTapped()
    func cameraTapped()
}

class NosturTextView: UITextView {
    var pastedImageDelegate: PastedImagesDelegate?

    override var delegate: UITextViewDelegate? {
        get { pastedImageDelegate }
        set { pastedImageDelegate = newValue as? PastedImagesDelegate }
    }

    // This gets called when user presses menu "Paste" option
    override func paste(_ sender: Any?) {
        if let image = UIPasteboard.general.image {
            pastedImageDelegate?.didPasteImage(image)
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
        pastedImageDelegate?.photoPickerTapped()
    }
    
    @objc func gifsTapped() {
        pastedImageDelegate?.gifsTapped()
    }
    
    @objc func cameraTapped() {
        pastedImageDelegate?.cameraTapped()
    }
    
}

public struct HighlightedTextEditor: UIViewRepresentable, HighlightingTextEditor {
    
    public struct Internals {
        public let textView: SystemTextView
        public let scrollView: SystemScrollView?
    }
    
    @Binding var text: String
    @Binding var pastedImages:[PostedImageMeta]
    
    var shouldBecomeFirstResponder: Bool
    
    let textView = NosturTextView()
    let highlightRules: [HighlightRule]
    var photoPickerTapped: PhotoPickerTappedCallback?
    var gifsTapped: GifsTappedCallback?
    var cameraTapped: CameraTappedCallback?
    
    private(set) var onEditingChanged: OnEditingChangedCallback?
    private(set) var onCommit: OnCommitCallback?
    private(set) var onSelectionChange: OnSelectionChangeCallback?
    private(set) var introspect: IntrospectCallback?
    
    public init(
        text: Binding<String>,
        pastedImages: Binding<[PostedImageMeta]>,
        shouldBecomeFirstResponder: Bool,
        highlightRules: [HighlightRule],
        photoPickerTapped: PhotoPickerTappedCallback? = nil,
        gifsTapped: GifsTappedCallback? = nil,
        cameraTapped: CameraTappedCallback? = nil
    ) {
        _text = text
        _pastedImages = pastedImages
        self.shouldBecomeFirstResponder = shouldBecomeFirstResponder
        self.highlightRules = highlightRules
        self.photoPickerTapped = photoPickerTapped
        self.gifsTapped = gifsTapped
        self.cameraTapped = cameraTapped
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
        textView.pastedImageDelegate = context.coordinator
        
        let doneToolbar: UIToolbar = UIToolbar(frame: CGRect.init(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        doneToolbar.barStyle = .default
        
        let cameraButton = UIButton(type: .system)
        cameraButton.setImage(UIImage(systemName: "camera"), for: .normal)
        cameraButton.tintColor = UIColor(Themes.default.theme.accent)
        cameraButton.addTarget(self, action: #selector(textView.cameraTapped), for: .touchUpInside)
        let camera = UIBarButtonItem(customView: cameraButton)
                       
        let photoButton = UIButton(type: .system)
        photoButton.setImage(UIImage(systemName: "photo"), for: .normal)
        photoButton.tintColor = UIColor(Themes.default.theme.accent)
        photoButton.addTarget(self, action: #selector(textView.photoPickerTapped), for: .touchUpInside)
        let photos = UIBarButtonItem(customView: photoButton)
    
    
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
    
    
        
        let toolbarItems: [UIBarButtonItem] = [camera, fixedSpace, photos, gifs, flexibleSpace]

        doneToolbar.setItems(toolbarItems, animated: false)
      

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
    
    public final class Coordinator: NSObject, UITextViewDelegate, PastedImagesDelegate {
        
        func didPasteImage(_ image: UIImage) {
            self.parent.pastedImages.append(PostedImageMeta(index: self.parent.pastedImages.count, imageData: image, type: .jpeg))
        }
        
        func photoPickerTapped() {
            guard let tapped = self.parent.photoPickerTapped else { return }
            tapped()
        }
        
        func gifsTapped() {
            guard let gifsTapped = self.parent.gifsTapped else { return }
            gifsTapped()
        }     
        
        func cameraTapped() {
            guard let cameraTapped = self.parent.cameraTapped else { return }
            cameraTapped()
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
            
//            let size = CGSize(width: textView.frame.size.width, height: .infinity)
//            let estimatedSize = textView.sizeThatFits(size)
//            guard textView.contentSize.height < 200.0 else { textView.isScrollEnabled = true; return }
//            textView.isScrollEnabled = false
//            textView.constraints.forEach { (constraint) in
//                if constraint.firstAttribute == .height {
//                    constraint.constant = estimatedSize.height
//                }
//            }
        }
        
        public func textViewDidChangeSelection(_ textView: UITextView) {
            guard let onSelectionChange = parent.onSelectionChange, !updatingUIView
            else { return }
            selectedTextRange = textView.selectedTextRange
            onSelectionChange([textView.selectedRange])
        }
        
        public func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onEditingChanged?()
        }
        
        public func textViewDidEndEditing(_ textView: UITextView) {
            parent.onCommit?()
        }
    }
}

public extension HighlightedTextEditor {
    func introspect(callback: @escaping IntrospectCallback) -> Self {
        var new = self
        new.introspect = callback
        return new
    }
    
    func onSelectionChange(_ callback: @escaping (_ selectedRange: NSRange) -> Void) -> Self {
        var new = self
        new.onSelectionChange = { ranges in
            guard let range = ranges.first else { return }
            callback(range)
        }
        return new
    }
    
    func onCommit(_ callback: @escaping OnCommitCallback) -> Self {
        var new = self
        new.onCommit = callback
        return new
    }
    
    func onEditingChanged(_ callback: @escaping OnEditingChangedCallback) -> Self {
        var new = self
        new.onEditingChanged = callback
        return new
    }
}
#endif
