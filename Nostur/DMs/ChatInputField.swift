//
//  ChatInputField.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//


import SwiftUI

struct ChatInputField: View {
    @Environment(\.theme) private var theme
    @Binding var message: String
    var attributedMessage: Binding<NSAttributedString>? = nil
    var startWithFocus: Bool = true
    var highlightMentions: Bool = false
    var replyingTo: NRChatMessage? = nil
    var quoting: NRChatMessage? = nil
    var focusRequest: Int = 0
    var onRemoveReference: (() -> Void)?
    var onSubmit: (() -> Void)?
    @State private var highlightedEditorHeight: CGFloat = 36
        
    enum FocusedField {
        case message
    }
    
    @FocusState private var focusedField: FocusedField?
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(spacing: 0) {
                if let replyingTo {
                    referencePreview(replyingTo)
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                }

                self.textField
                    .textInputAutocapitalization(.sentences)
                    .padding(10)
                    .padding(.trailing, 40)
                    .background(Color.clear)
                    .focused($focusedField, equals: .message)
                    .submitLabel(.send)
                    .onSubmit {
                        if let onSubmit {
                            onSubmit()
                        }
                        if IS_CATALYST {
                            focusedField = .message
                        }
                    }

                if let quoting {
                    referencePreview(quoting)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
            }
            .frame(maxWidth: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    Button("Send", systemImage: "arrow.up") {
                        if let onSubmit {
                            onSubmit()
                        }
                        focusedField = nil
                    }
                    .buttonStyleGlassProminent()
                    .labelStyle(.iconOnly)
                    .tint(theme.accent)
                    .fontWeightBold()
                    .keyboardShortcut(.defaultAction)
                    .disabled(message.isEmpty)
                    .onSubmit {
                        if let onSubmit {
                            onSubmit()
                        }
                        if IS_CATALYST {
                            focusedField = .message
                        }
                    }
                    .opacity(message.isEmpty ? 0.5 : 1.0)
                    .padding(.trailing, 5)
                    .padding(.bottom, 5)
                }
        }
        .background(theme.listBackground)
        .containerShape(.rect(cornerRadius: 14))
        .padding(1)
        .background(theme.lineColor)
        .containerShape(.rect(cornerRadius: 14))
        .padding([.leading, .trailing], 10)
        .onAppear {
            if startWithFocus {
                focusedField = .message 
            }
        }
        .onChange(of: focusRequest) { _ in
            focusedField = .message
        }
    }

    private func referencePreview(_ message: NRChatMessage) -> some View {
        EmbeddedChatMessage(nrChatMessage: message, isSentByCurrentUser: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                Button("Remove", systemImage: "xmark.circle.fill") {
                    withAnimation {
                        onRemoveReference?()
                    }
                }
                .labelStyle(.iconOnly)
                .offset(x: -3, y: 3)
            }
    }
    
    @ViewBuilder
    private var textField: some View {
        if highlightMentions {
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text(String(localized:"Type your message...", comment:"Placeholder for input field for new direct message"))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                MentionHighlightingTextView(
                    text: $message,
                    attributedText: attributedMessage,
                    height: $highlightedEditorHeight,
                    accentColor: UIColor(theme.accent),
                    onSubmit: onSubmit
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: min(highlightedEditorHeight, 120))
            .clipped()
        }
        else if #available(iOS 16.0, *) {
            TextField(String(localized:"Type your message...", comment:"Placeholder for input field for new direct message"), text: $message, axis: .vertical)
                .lineLimit(1...5)
        } else {
            TextField(String(localized:"Type your message...", comment:"Placeholder for input field for new direct message"), text: $message)
        }
    }
}

private struct MentionHighlightingTextView: UIViewRepresentable {
    @Binding var text: String
    let attributedText: Binding<NSAttributedString>?
    @Binding var height: CGFloat
    let accentColor: UIColor
    let onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .nosturBody()
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 5
        textView.textContainer.widthTracksTextView = true
        textView.returnKeyType = .send
        textView.tintColor = accentColor
        if #available(iOS 17.0, *) {
            textView.inlinePredictionType = .default
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyExternalTextIfNeeded(to: textView)
        context.coordinator.styleSemanticMentions(in: textView)
        context.coordinator.syncAttributedText(from: textView)
        context.coordinator.updateHeight(of: textView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MentionHighlightingTextView
        private var isUpdating = false

        init(parent: MentionHighlightingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            parent.text = textView.text
            styleSemanticMentions(in: textView)
            syncAttributedText(from: textView)
            updateHeight(of: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            if replacement == "\n" {
                parent.onSubmit?()
                return false
            }

            invalidateSemanticMentions(in: range, textView: textView)
            return true
        }

        func applyExternalTextIfNeeded(to textView: UITextView) {
            guard textView.text != parent.text else { return }
            isUpdating = true
            defer { isUpdating = false }

            let oldText = textView.text ?? ""
            let selectedRange = textView.selectedRange
            let replacement = NSMutableAttributedString(string: parent.text)
            let fullRange = NSRange(location: 0, length: replacement.length)
            replacement.addAttributes([
                .font: UIFont.nosturBody(),
                .foregroundColor: UIColor.label
            ], range: fullRange)

            if let attributedText = parent.attributedText?.wrappedValue,
               attributedText.string == parent.text {
                for run in attributedText.nosturMentionRuns()
                where NSMaxRange(run.range) <= replacement.length
                    && replacement.attributedSubstring(from: run.range).string == run.text {
                    replacement.addAttribute(
                        .nosturMentionPubkey,
                        value: run.pubkey,
                        range: run.range
                    )
                }
            }

            textView.textStorage.setAttributedString(replacement)
            textView.selectedRange = selectionAfterExternalTextChange(
                from: oldText,
                to: parent.text,
                selectedRange: selectedRange
            )
        }

        func styleSemanticMentions(in textView: UITextView) {
            let fullRange = NSRange(location: 0, length: textView.textStorage.length)
            if fullRange.length > 0 {
                textView.textStorage.addAttributes([
                    .font: UIFont.nosturBody(),
                    .foregroundColor: UIColor.label
                ], range: fullRange)
            }
            for run in textView.attributedText.nosturMentionRuns() {
                textView.textStorage.addAttributes([
                    .font: UIFont.nosturBody().bold,
                    .foregroundColor: parent.accentColor
                ], range: run.range)
            }
            setDefaultTypingAttributes(on: textView)
        }

        private func setDefaultTypingAttributes(on textView: UITextView) {
            textView.typingAttributes = [
                .font: UIFont.nosturBody(),
                .foregroundColor: UIColor.label
            ]
        }

        func syncAttributedText(from textView: UITextView) {
            guard parent.attributedText?.wrappedValue != textView.attributedText else { return }
            parent.attributedText?.wrappedValue = NSAttributedString(
                attributedString: textView.attributedText
            )
        }

        private func invalidateSemanticMentions(in range: NSRange, textView: UITextView) {
            let storage = textView.textStorage
            let inspectionRange: NSRange
            if range.length > 0 {
                inspectionRange = range
            } else if range.location < storage.length {
                inspectionRange = NSRange(location: range.location, length: 1)
            } else {
                return
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
                storage.addAttributes([
                    .font: UIFont.nosturBody(),
                    .foregroundColor: UIColor.label
                ], range: mentionRange)
            }
        }

        func updateHeight(of textView: UITextView) {
            let fittingSize = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
            let newHeight = max(36, textView.sizeThatFits(fittingSize).height)
            textView.isScrollEnabled = newHeight > 120
            if abs(parent.height - newHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.height = newHeight
                }
            }
        }
    }
}

func selectionAfterExternalTextChange(
    from oldText: String,
    to newText: String,
    selectedRange: NSRange
) -> NSRange {
    let oldText = oldText as NSString
    let newText = newText as NSString
    let comparableLength = min(oldText.length, newText.length)

    var commonPrefixLength = 0
    while commonPrefixLength < comparableLength,
          oldText.character(at: commonPrefixLength) == newText.character(at: commonPrefixLength) {
        commonPrefixLength += 1
    }

    var commonSuffixLength = 0
    while commonSuffixLength < oldText.length - commonPrefixLength,
          commonSuffixLength < newText.length - commonPrefixLength,
          oldText.character(at: oldText.length - commonSuffixLength - 1)
            == newText.character(at: newText.length - commonSuffixLength - 1) {
        commonSuffixLength += 1
    }

    let oldChangedEnd = oldText.length - commonSuffixLength
    let newChangedEnd = newText.length - commonSuffixLength
    let newLocation: Int
    if selectedRange.location < commonPrefixLength
        || (selectedRange.location == commonPrefixLength && oldChangedEnd > commonPrefixLength) {
        newLocation = selectedRange.location
    } else if selectedRange.location >= oldChangedEnd {
        newLocation = selectedRange.location + (newChangedEnd - oldChangedEnd)
    } else {
        newLocation = newChangedEnd
    }

    return NSRange(
        location: min(max(0, newLocation), newText.length),
        length: 0
    )
}

// Copy pasta with replyingNow and quotingNow added
struct DMChatInputField: View {
    @Environment(\.theme) private var theme
    @Binding var message: String
    @ObservedObject var vm: ConversionVM
    var startWithFocus: Bool = true
    var onSubmit: (() -> Void)?
    var onPickPhotos: (() -> Void)?
    var onPickFiles: (() -> Void)?

    enum FocusedField {
        case message
    }
    
    @FocusState private var focusedField: FocusedField?
    
    private var showAttachmentButton: Bool {
        vm.conversationVersion == 17 && SettingsStore.shared.defaultMediaUploadService.name == BLOSSOM_LABEL
    }
    
    private var canSend: Bool {
        !message.isEmpty || vm.pendingFileAttachment != nil
    }

    private var plusButtonIcon: some View {
        Image(systemName: "plus.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
            .foregroundStyle(theme.accent)
    }

    // NIP-40 composer chip, shown while this conversation has disappearing messages enabled.
    @ViewBuilder
    private var expiryChip: some View {
        if let duration = vm.expiryDuration {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                Text("Disappears in ~\(DMExpiry.presetLabel(forDuration: duration))")
            }
            .font(.footnote)
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.accent.opacity(0.16), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
    }

    var body: some View {
        HStack(alignment: .center) {
            if vm.pendingFileAttachment == nil {
                Group {
                    if showAttachmentButton {
                        Menu {
                            Button("Photos", systemImage: "photo") { onPickPhotos?() }
                            Button("Files", systemImage: "doc") { onPickFiles?() }
                        } label: {
                            plusButtonIcon
                        }
                    }
                }
                .padding(.leading, 4)
            }
            VStack(alignment: .center) {

                expiryChip

                if let replyingNow = vm.replyingNow {
                    EmbeddedChatMessage(nrChatMessage: replyingNow, isSentByCurrentUser: false)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay(alignment: .topTrailing) {
                            Button("Remove", systemImage: "xmark.circle.fill") {
                                withAnimation {
                                    vm.replyingNow = nil
                                }
                            }
                            .labelStyle(.iconOnly)
                            .offset(x: -3, y: 3)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                }
                
                // File attachment preview
                if let pending = vm.pendingFileAttachment {
                    filePreview(pending)
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                }
                
                self.textField
                    .textInputAutocapitalization(.sentences)
                    .padding(10)
                    .padding(.trailing, 40)
                    .background(Color.clear)
                    .focused($focusedField, equals: .message)
                    .submitLabel(.send)
                    .onSubmit {
                        if let onSubmit {
                            onSubmit()
                        }
                        if IS_CATALYST {
                            focusedField = .message
                        }
                    }
                
                if let quotingNow = vm.quotingNow {
                    EmbeddedChatMessage(nrChatMessage: quotingNow, isSentByCurrentUser: false)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay(alignment: .topTrailing) {
                            Button("Remove", systemImage: "xmark.circle.fill") {
                                withAnimation {
                                    vm.quotingNow = nil
                                    focusedField = .message
                                }
                            }
                            .labelStyle(.iconOnly)
                            .offset(x: -3, y: 3)
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button("Send", systemImage: "arrow.up") {
                    if let onSubmit {
                        onSubmit()
                    }
                    focusedField = nil
                }
                .buttonStyleGlassProminent()
                .labelStyle(.iconOnly)
                .tint(theme.accent)
                .fontWeightBold()
                .keyboardShortcut(.defaultAction)
                .disabled(!canSend)
                .onSubmit {
                    if let onSubmit {
                        onSubmit()
                    }
                    if IS_CATALYST {
                        focusedField = .message
                    }
                }
                .opacity(canSend ? 1.0 : 0.5)
                .padding(.trailing, 5)
                .padding(.bottom, 5)
            }
        }
        .background(theme.listBackground)
        .containerShape(.rect(cornerRadius: 14))
        .padding(1)
        .background(theme.lineColor)
        .containerShape(.rect(cornerRadius: 14))
        .padding([.leading, .trailing], 10)
        .onAppear {
            if startWithFocus {
                focusedField = .message
            }
        }
        .onValueChange(vm.replyingNow) { oldValue, newValue in
            if oldValue == nil && newValue != nil { // auto focus after adding reply
                focusedField = .message
            }
        }
        .onValueChange(vm.quotingNow) { oldValue, newValue in
            if oldValue == nil && newValue != nil { // auto focus after adding quote
                focusedField = .message
            }
        }
    }
    
    @ViewBuilder
    private func filePreview(_ pending: PendingFileAttachment) -> some View {
        HStack(spacing: 8) {
            if pending.isImage, let thumb = pending.thumbnailImage {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                Image(systemName: iconForMimeType(pending.mimeType))
                    .font(.title)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(theme.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(pending.fileName ?? pending.fileExtension)
                    .font(.footnote.bold())
                    .lineLimit(1)
                Text(pending.formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(theme.background.opacity(0.5))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            Button("Remove", systemImage: "xmark.circle.fill") {
                withAnimation {
                    vm.pendingFileAttachment = nil
                }
            }
            .labelStyle(.iconOnly)
            .offset(x: 5, y: -5)
        }
    }
    
    private func iconForMimeType(_ mimeType: String) -> String {
        switch mimeType {
        case let t where t.contains("pdf"):
            return "doc.richtext"
        case let t where t.contains("spreadsheet") || t.contains("excel") || t.contains("csv"):
            return "tablecells"
        case let t where t.contains("word") || t.contains("document"):
            return "doc.text"
        case let t where t.contains("zip") || t.contains("archive") || t.contains("compressed"):
            return "doc.zipper"
        case let t where t.contains("text"):
            return "doc.plaintext"
        case let t where t.contains("audio"):
            return "waveform"
        case let t where t.contains("video"):
            return "film"
        default:
            return "doc"
        }
    }
    
    @ViewBuilder
    private var textField: some View {
        if #available(iOS 16.0, *) {
            TextField(String(localized:"Type your message...", comment:"Placeholder for input field for new direct message"), text: $message, axis: .vertical)
        } else {
            TextField(String(localized:"Type your message...", comment:"Placeholder for input field for new direct message"), text: $message)
        }
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var text = ""
    VStack {
        Spacer()
        ChatInputField(message: $text)
            .padding(5)
    }
    .environment(\.theme, Themes.DEFAULT)
}

@available(iOS 17.0, *)
#Preview("DM input") {
    @Previewable @State var text = ""
    
    @Previewable @StateObject var vmQuotingNow = ConversionVM(
        participants: ["9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                       "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33"],
        ourAccountPubkey: "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33",
        parentDMsVM: DMsVM.shared
    )
    
    @Previewable @StateObject var vmReplyingNow = ConversionVM(
        participants: ["9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                       "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33"],
        ourAccountPubkey: "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33",
        parentDMsVM: DMsVM.shared
    )
    
    VStack {
        DMChatInputField(message: $text, vm: vmQuotingNow)
            .padding(5)
        
        DMChatInputField(message: $text, vm: vmReplyingNow)
            .padding(5)
        
        Spacer()
    }
    .environment(\.theme, Themes.DEFAULT)
    .onAppear {
        vmQuotingNow.quotingNow = NRChatMessage(
            nEvent: NEvent(
                id: "173f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879",
                publicKey: "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33",
                createdAt: NTimestamp.init(date: Date()),
                content: "Hello there! A bit longer. This message is a few lines long. So here is a newline.\nAnd I'm starting another sentence here. What's up!",
                kind: .directMessage,
                tags: [],
                signature: ""
            )
        )
        
        vmReplyingNow.replyingNow = NRChatMessage(
            nEvent: NEvent(
                id: "173f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879",
                publicKey: "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33",
                createdAt: NTimestamp.init(date: Date()),
                content: "Hello again!",
                kind: .directMessage,
                tags: [],
                signature: ""
            )
        )
    }
}
