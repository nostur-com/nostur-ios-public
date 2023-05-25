//
//  Testing.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/05/2023.
//

import SwiftUI

struct Testing: View {
    @State var text = ""
    @State var pastedImages:[UIImage] = []
    var body: some View {
        HighlightedTextEditor(
            text: $text,
            pastedImages: $pastedImages,
            shouldBecomeFirstResponder: true,
            highlightRules: NewNoteText.rules,
            photoPickerTapped: {
                
            },
            gifsTapped: {
                
            }
        )
        .frame(height: 150)
    }
}

struct Testing_Previews: PreviewProvider {
    static var previews: some View {
        Testing()
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}
