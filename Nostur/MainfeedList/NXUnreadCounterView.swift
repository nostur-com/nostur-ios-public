//
//  NXUnreadCounterView.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI

struct NXUnreadCounterView: View {
    
    @EnvironmentObject private var themes: Themes
    public let count: Int
    
    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .foregroundColor(themes.theme.accent)
            .frame(width: 65, height: 40)
            .overlay(alignment: .leading) {
                Text(count.description)
                    .animation(.snappy, value: count)
                    .rollingNumber()
                    .fixedSize()
                    .frame(width: 35, alignment: .center)
                    .padding(.leading, 5)
                    
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "arrow.up")
                    .padding(.trailing, 8)
            }
            .fontWeightBold()
            .foregroundColor(.white)
            .opacity(count > 0 ? 1.0 : 0)
    }
}

#Preview {
    NXUnreadCounterView(count: 321)
        .environmentObject(Themes.default)
}
