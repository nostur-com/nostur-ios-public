//
//  FixedPFP.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/05/2024.
//

import SwiftUI
import NukeUI

struct FixedPFP: View {
    public let picture: URL
    var body: some View {
        MiniPFP(pictureUrl: picture)
            .overlay(
                RoundedRectangle(cornerRadius: 20.0)
                    .stroke(.secondary, lineWidth: 1)
            )
                
    }
}

func hasFPFcacheFor(_ imageRequest: ImageRequest) -> Bool {
    return ImageProcessing.shared.pfp.cache.containsCachedImage(for: imageRequest)
}

#Preview {
    FixedPFP(picture: URL(string: "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972")!)
}
