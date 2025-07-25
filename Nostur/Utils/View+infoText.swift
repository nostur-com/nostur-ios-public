//
//  View+infoText.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/02/2025.
//

import SwiftUI
import NavigationBackport

public extension View {
    
    func infoText(_ text: String) -> some View {
        modifier(InfoText(text: text))
    }
}

private struct InfoText: ViewModifier {
    
    @Environment(\.theme) private var theme
    let text: String
    
    @State var showInfoSheet = false

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                showInfoSheet = true
            }
            .sheet(isPresented: $showInfoSheet, onDismiss: {
                showInfoSheet = false
            }) {
                NBNavigationStack {
                    VStack {
                        Image(systemName: "info.square.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50)
                            .padding(.bottom, 10)
                        Text(text)
                            .presentationDetentsMedium()
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .environment(\.theme, theme)
                    .presentationBackgroundCompat(theme.listBackground)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("OK") {
                                showInfoSheet = false
                            }
                        }
                    }
                }
            }
    }
}

#Preview {
    Text("Tap me")
        .infoText("This is some extra info")
}
