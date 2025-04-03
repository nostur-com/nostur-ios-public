//
//  NRNavigationStack.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import SwiftUI
import NavigationBackport

struct NRNavigationStack<Content: View>: View {

    @ViewBuilder
    public let content: Content
    
    var body: some View {
        NBNavigationStack {
            AppEnvironment {
                content
            }       
        }
        .nbUseNavigationStack(.never)
    }
}

// Note: dismiss doesn't work with NRSheetNavigationStack in .sheet. So use NBNavigationStack directly in sheet. .presentationDetents also don't work when using this. wtf!
struct NRSheetNavigationStack<Content: View>: View {
    
    @ViewBuilder
    public let content: Content
    
    var body: some View {
        NBNavigationStack {
            AvailableWidthContainer {
                AppEnvironment {
                    content
                }
            }
        }
        .nbUseNavigationStack(.never)
        .presentationBackgroundCompat(Themes.default.theme.listBackground)
    }
}
