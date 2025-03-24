//
//  NoInternetConnectionBanner.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2025.
//

import SwiftUI

struct NoInternetConnectionBanner: View {
    @EnvironmentObject private var networkMonitor:NetworkMonitor
    
    var body: some View {
        if networkMonitor.isDisconnected {
            Text("\(Image(systemName: "wifi.exclamationmark")) No internet connection")
                .font(.caption)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(5)
                .background(.red)
        }
        else {
            EmptyView()
        }
    }
}
