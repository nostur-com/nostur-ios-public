//
//  NXList.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2025.
//


// List with boilerplate for reuse instead of default List. Sets correct list background, row background
struct NXList<Content: View>: View {
    @Environment(\.theme) private var theme
    private var content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        List {
            Group {
                content
            }
            .listRowBackground(theme.background)
            .listRowInsets(EdgeInsets())
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
        }
        .background(theme.listBackground)
        .listRowInsets(EdgeInsets())
        .listStyle(.plain)
    }
}