//
//  ChatInputField.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//


import SwiftUI

struct ChatInputField: View {
    @Binding var message:String
    var onSubmit:(() -> Void)?
    
    enum FocusedField {
        case message
    }
    
    @FocusState private var focusedField: FocusedField?
    
    var body: some View {
        HStack {
            TextField(String(localized:"Type your message...", comment:"Placeholder for input field for new direct message"), text: $message)
                .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 0))
                .background(Color.clear)
                .focused($focusedField, equals: .message)
            
            Button(action: {
                if let onSubmit {
                    onSubmit()
                }
            }) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20))
                    .padding(.trailing, 10)
            }
            .accentColor(Color("AccentColor"))
        }
        .background(Color(UIColor.systemGray6))
        .cornerRadius(25)
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
        )
        .padding([.leading, .trailing], 10)
        .onAppear { focusedField = .message }
    }
}


struct ChatInputField_ContentView: View {
    @State var text = ""
    var body: some View {
        VStack {
            Spacer()
            ChatInputField(message: $text)
                .padding(.bottom, 10)
        }
    }
}

struct ChatInputField_Previews: PreviewProvider {
    static var previews: some View {
        ChatInputField_ContentView()
    }
}
