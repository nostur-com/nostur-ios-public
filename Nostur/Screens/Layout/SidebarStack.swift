//
//  SidebarStack.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI

final class SideBarModel: ObservableObject {
    @Published var showSidebar = false
}

struct SideBarStack<SidebarContent: View, Content: View>: View {
    
    let sidebarContent: SidebarContent
    let mainContent: Content
    let sidebarWidth: CGFloat
     
    @EnvironmentObject var sm:SideBarModel

    @State var sidebarOffsetX = -310.0
    @State var mainContentOffsetX = 0.0
    
    init(sidebarWidth: CGFloat, @ViewBuilder sidebar: ()->SidebarContent, @ViewBuilder content: ()->Content) {
        self.sidebarWidth = sidebarWidth
        sidebarContent = sidebar()
        mainContent = content()

        self.sidebarOffsetX = -1 * sidebarWidth
        self.mainContentOffsetX = 0.0
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        ZStack(alignment: .leading) {
            sidebarContent
                .frame(width: sidebarWidth, alignment: .center)
                .offset(x: sidebarOffsetX)
            mainContent
                .overlay(
                    Group {
                        if sm.showSidebar {
                            Color.white
                                .opacity(0.01)
                                .onTapGesture {
                                    sm.showSidebar = false
                                }
                        } else {
                            Color.clear
                            .opacity(0)
                            .onTapGesture {
                                sm.showSidebar = false
                            }
                        }
                    }
                )
                .offset(x: mainContentOffsetX)
                .opacity(sm.showSidebar ? 0.25 : 1.0)
        }
        .onChange(of: sm.showSidebar) { shouldShowSidebar in
            withAnimation(.easeOut(duration: 0.1)) {
                sidebarOffsetX = sm.showSidebar ? 0 : -1 * sidebarWidth
                mainContentOffsetX = sm.showSidebar ? sidebarWidth : 0
            }
        }
    }
}
