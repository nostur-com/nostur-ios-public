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
            
            Button(action: {
                if let onSubmit {
                    onSubmit()
                }
                focusedField = nil
            }) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20))
                    .padding(.trailing, 10)
            }
            .keyboardShortcut(.defaultAction)
            .onSubmit {
                if let onSubmit {
                    onSubmit()
                }
            }
            .accentColor(theme.accent)
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
}


struct ChatInputField_ContentView: View {
    @State var text = ""
    var body: some View {
        VStack {
            Spacer()
            ChatInputField(message: $text)
                .padding(.bottom, 10)
    @ViewBuilder
    private var textField: some View {
        if #available(iOS 16.0, *) {
            TextField(String(localized:"Type your message...", comment:"Placeholder for input field for new direct message"), text: $message, axis: .vertical)
        } else {
            TextField(String(localized:"Type your message...", comment:"Placeholder for input field for new direct message"), text: $message)
        }
    }
}

struct ChatInputField_Previews: PreviewProvider {
    static var previews: some View {
        ChatInputField_ContentView()
            .environmentObject(Themes.default)
    }
}
