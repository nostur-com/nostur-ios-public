//
//  MacListsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/05/2023.
//

import SwiftUI

struct MacListsView: View {
    let SIDEBAR_WIDTH = 70.0
    @State var columnsCount = 4
    
    var body: some View {
//        let _ = Self._printChanges()

        GeometryReader { geo in
            HStack {
                // Tabs on the side
                SideTabs(columnsCount: $columnsCount)
                    .frame(width: SIDEBAR_WIDTH)
                
                // Main list (following/notifications/bookmarks)
                MacList(availableWidth: columnSize(geo.size.width)) {
                    MainView()
                }
                
                // Extra lists (+ -)
                ForEach(0..<max(1,columnsCount), id:\.self) { columnIndex in
                    MacList(availableWidth: columnSize(geo.size.width)) {
                        Color.random
                    }
                        .id(columnIndex)
                }
            }
        }
    }
    
    func columnSize(_ availableWidth:CGFloat) -> CGFloat {
        CGFloat((availableWidth - SIDEBAR_WIDTH)/Double(columnsCount + 1))
    }
}


struct MacList<Content: View>: View {
    
    let content: Content
    let dim:DIMENSIONS

    init(availableWidth:CGFloat = 600, @ViewBuilder content: ()->Content) {
        self.content = content()
        self.dim = DIMENSIONS()
        self.dim.listWidth = CGFloat(availableWidth)
    }
    
    var body: some View {
        content
            .environmentObject(dim)
    }
}


struct SideTabs:View {
    @Binding var columnsCount:Int
    var body: some View {
        VStack {
            Button { addColumn() } label: {
                Image(systemName: "rectangle.righthalf.inset.fill.arrow.right")
            }
            Button { removeColumn() } label: {
                Image(systemName: "rectangle.lefthalf.inset.fill.arrow.left")
            }
            Spacer()
        }
        .padding(.top, 100)
    }
    
    func addColumn() {
        guard columnsCount < 10 else { return }
        columnsCount += 1
    }
    
    func removeColumn() {
        guard columnsCount > 1 else { return }
        columnsCount -= 1
    }
}

struct MacListsView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer(previewDevice:PreviewDevice(rawValue: "My Mac (Mac Catalyst)")) {
            MacListsView()
        }
    }
}
