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
        HStack(alignment: .bottom) {
            self.textField
                .textInputAutocapitalization(.never)
                .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 0))
                .background(Color.clear)
                .focused($focusedField, equals: .message)
                .submitLabel(.send)
                .onSubmit {
                    if let onSubmit {
                        onSubmit()
                    }
                }
            
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
            .onSubmit {
                if let onSubmit {
                    onSubmit()
                }
            }
            .padding(.trailing, 8)
            .padding(.bottom, 5)
            
        }
        .background(theme.listBackground)
        .cornerRadius(25)
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
        )
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
            .padding(.bottom, 10)
    }
    .environment(\.theme, Themes.DEFAULT)
}
