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
    var startWithFocus: Bool = true
    var onSubmit: (() -> Void)?
        
    enum FocusedField {
        case message
    }
    
    @FocusState private var focusedField: FocusedField?
    
    var body: some View {
        HStack(alignment: .center) {
            self.textField
                .textInputAutocapitalization(.sentences)
                .padding(10)
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

// Copy pasta with replyingNow and quotingNow added
struct DMChatInputField: View {
    @Environment(\.theme) private var theme
    @Binding var message: String
    @ObservedObject var vm: ConversionVM
    var startWithFocus: Bool = true
    var onSubmit: (() -> Void)?

    enum FocusedField {
        case message
    }
    
    @FocusState private var focusedField: FocusedField?
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .center) {
                
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
                
                self.textField
                    .textInputAutocapitalization(.sentences)
                    .padding(10)
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
        ourAccountPubkey: "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33"
    )
    
    @Previewable @StateObject var vmReplyingNow = ConversionVM(
        participants: ["9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                       "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33"],
        ourAccountPubkey: "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33"
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
