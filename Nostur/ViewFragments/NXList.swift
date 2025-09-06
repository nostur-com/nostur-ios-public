//
//  NXList.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2025.
//
import SwiftUI

// List with boilerplate for reuse instead of default List. Sets correct list background, row background
// with plain flag to use default SwiftUI spacing
struct NXList<Content: View>: View {
    @Environment(\.theme) private var theme
    private var content: Content
    private var plain: Bool
    
    init(plain: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.plain = plain
    }
    
    var body: some View {
        if plain {
            self.plainBody
        }
        else {
            self.normalBody
        }
    }
    
    @ViewBuilder
    var normalBody: some View {
        List {
            Group {
                content
            }
//            .foregroundColor(theme.accent)
            .listRowBackground(theme.background)
        }
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
    }
    
    @ViewBuilder
    var plainBody: some View {
        List {
            Group {
                content
            }
            .foregroundColor(theme.accent)
            .listRowBackground(theme.background)
            .listRowInsets(EdgeInsets())
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
        }
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        .listRowInsets(EdgeInsets())
        .listStyle(.plain)
    }
}
