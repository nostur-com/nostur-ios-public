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
    private var showListRowSeparator: Bool
    
    init(plain: Bool = false, showListRowSeparator: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.plain = plain
        self.showListRowSeparator = showListRowSeparator
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
            .listRowBackground(theme.background)
            
            .modifier {
                if #available(iOS 26.0, *), IS_CATALYST {
                    $0.listRowBackground(theme.background)
                      .listRowInsets(.init(top: 10, leading: 20, bottom: 8, trailing: 10))
                }
                else {
                    $0
                }
            }
        }
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        
        .modifier {
            if #available(iOS 26.0, *), IS_CATALYST {
                $0.listSectionSpacing(.compact)
            }
            else {
                $0
            }
        }
    }
    
    @ViewBuilder
    var plainBody: some View {
        List {
            Group {
                content
            }
            .foregroundColor(theme.accent)
            .listRowBackground(theme.listBackground)
            .listRowInsets(EdgeInsets())
            .modifier {
                if showListRowSeparator, #available(iOS 16, *) {
                    $0.listRowSeparator(.visible)
                       .alignmentGuide(.listRowSeparatorLeading) { _ in
                            return 10
                       }
                }
                else {
                    $0.listRowSeparator(.hidden)
                }
            }
        }
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        .listRowInsets(EdgeInsets())
        .listStyle(.plain)
    }
}
