//
//  SidebarStack.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI

struct SideBarStack<SidebarContent: View, Content: View>: View {
    
    let sidebarContent: SidebarContent
    let mainContent: Content
    let sidebarWidth: CGFloat
    @Binding var showSidebar: Bool
    @State var sidebarOffsetX = -285.0
    @State var mainContentOffsetX = 0.0
    
    init(sidebarWidth: CGFloat, showSidebar: Binding<Bool>, @ViewBuilder sidebar: ()->SidebarContent, @ViewBuilder content: ()->Content) {
        self.sidebarWidth = sidebarWidth
        self._showSidebar = showSidebar
        sidebarContent = sidebar()
        mainContent = content()
        
        if (showSidebar.wrappedValue) {
            self.sidebarOffsetX = 0
            self.mainContentOffsetX = sidebarWidth
        }
        else {
            self.sidebarOffsetX = -1 * sidebarWidth
            self.mainContentOffsetX = 0.0
        }
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            sidebarContent
                .frame(width: sidebarWidth, alignment: .center)
                .offset(x: sidebarOffsetX)
            mainContent
                .overlay(
                    Group {
                        if showSidebar {
                            Color.white
                                .opacity(0.01)
                                .onTapGesture {
                                    self.showSidebar = false
                                }
                        } else {
                            Color.clear
                            .opacity(0)
                            .onTapGesture {
                                self.showSidebar = false
                            }
                        }
                    }
                )
                .offset(x: mainContentOffsetX)
        }
        .onChange(of: showSidebar) { shouldShowSidebar in
            withAnimation {
                sidebarOffsetX = showSidebar ? 0 : -1 * sidebarWidth
                mainContentOffsetX = showSidebar ? sidebarWidth : 0
            }
        }
    }
}
