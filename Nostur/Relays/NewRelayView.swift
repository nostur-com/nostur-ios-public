//
//  NewRelayView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/01/2023.
//

import SwiftUI

struct NewRelayView: View {
    
    @Environment(\.dismiss) private var dismiss
    @State var url = "wss://"
    
    var accentColor: Color = .accentColor
    var grayBackground: Color = Color.gray.opacity(0.2)
    
    var onAdd:((_ url:String) -> Void)? = nil
    
    var body: some View {
        
        VStack{
            Text("Add relay")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
                .fontWeight(.semibold)
                .padding(.bottom, 20)
            TextField("wss://relay...", text: $url)
                .keyboardType(.URL)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .padding()
                .background(grayBackground)
                .cornerRadius(5.0)
                .padding(.bottom, 20)
            
            Button {
                if (onAdd != nil) {
                    onAdd!(url)
                }
                dismiss()
            } label: {
                Text("Add")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(width: 220, height: 60)
                    .background(accentColor)
                    .cornerRadius(15.0)
            }
            Spacer()
            
        }.padding()
    }
}

struct NewRelayView_Previews: PreviewProvider {
    static var previews: some View {
        NewRelayView()
    }
}
