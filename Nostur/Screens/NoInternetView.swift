//
//  NoInternetView.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import SwiftUI

struct NoInternetView: View {
    var body: some View {
        VStack(alignment: .center) {
            Image(systemName: "wifi.exclamationmark")
                .resizable()
                .scaledToFit()
                .frame(height: 100)
            Text("Internet connection unavailable")
                .font(.title)
            Text("Please try again when there is a connection")
        }
        .wowBackground()
    }
}
