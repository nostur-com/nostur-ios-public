//
//  CopyableTextView.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/09/2024.
//

import SwiftUI

struct CopyableTextView: View {
    let text: String
    
    @State private var tapped1 = false
    
    var body: some View {
        HStack {
            Text(text)
            Image(systemName: tapped1 ? "doc.on.doc.fill" : "doc.on.doc")
                .font(.footnote)
        }
        .opacity(text == "" ? 0.0 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            UIPasteboard.general.string = text
            tapped1 = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                tapped1 = false
            }
        }
    }
}

#Preview {
    CopyableTextView(text: "npub1n0sturny6w9zn2wwexju3m6asu7zh7jnv2jt2kx6tlmfhs7thq0qnflahe")
        .lineLimit(1)
        .frame(width: 140)
}
