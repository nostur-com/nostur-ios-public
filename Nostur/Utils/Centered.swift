//
//  Centered.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/03/2023.
//

import SwiftUI

struct CenteredProgressView: View {
    var message: String?
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ProgressView(label: {
                    if let message {
                        Text(message)
                    }
                })
                Spacer()
            }
            Spacer()
        }
    }
}

#Preview {
    CenteredProgressView()
}


#Preview("with text") {
    CenteredProgressView(message: "Waiting for something...")
}
