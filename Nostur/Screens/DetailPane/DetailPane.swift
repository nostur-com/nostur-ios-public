//
//  DetailPane.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2023.
//

import SwiftUI
import UIKit

struct DetailPane: View {
    @StateObject private var dim = DIMENSIONS.shared
    @StateObject var tm = DetailTabsModel()
    @State var offsetX = 200.0

    init() {
        UIScrollView.appearance().bounces = false
    }
    
    var body: some View {
        
        VStack(spacing:0) {
            Color.clear.frame(height: 0)
                .modifier(SizeModifier())
                .onPreferenceChange(SizePreferenceKey.self) { size in
                    guard size.width > 0 else { return }
                    dim.listWidth = size.width
                    L.og.info("🟣🟣🟣🟣🟣 NEW DETAIL WIDTH \(size.width) -- Scale: \(UIScreen.main.scale) ")
                }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing:0) {
                        ForEach(tm.tabs.indices, id:\.self) { index in
                            NosturTabButton(
                                isSelected: tm.selected == tm.tabs[index],
                                onSelect: {
                                    let t = tm.tabs[index]
                                    tm.selected = t
                                    if let nrPost = tm.selected?.nrPost {
                                        EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NosturTabButton.onSelect")
                                        if nrPost.kind == 30023 {
                                            req(RM.getPREventReferences(aTag: nrPost.aTag, subscriptionId: "REALTIME-DETAIL"))
                                        }
                                        else {
                                            req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "REALTIME-DETAIL"))
                                        }
                                    }
                                },
                                onClose: {
                                    if (tm.selected == tm.tabs[index]) {
                                        if (index != 0) {
                                            tm.selected = tm.tabs[(index - 1)]
                                            if let id = tm.selected?.id {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                    proxy.scrollTo(id)
                                                }
                                            }
                                        }
                                        else if (tm.tabs.count > 1) {
                                            tm.selected = tm.tabs[1]
                                            if let id = tm.selected?.id {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                    proxy.scrollTo(id)
                                                }
                                            }
                                        }
                                        if let nrPost = tm.selected?.nrPost {
                                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NosturTabButton.onClose")
                                            if nrPost.kind == 30023 {
                                                req(RM.getPREventReferences(aTag: nrPost.aTag, subscriptionId: "REALTIME-DETAIL"))
                                            }
                                            else {
                                                req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "REALTIME-DETAIL"))
                                            }
                                        }
                                        else {
                                            // Close REALTIME-DETAIL subscription if the new active tab is not a nrPost
                                            let closeMessage = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: "REALTIME-DETAIL"))
                                            SocketPool.shared.sendMessage(closeMessage)
                                        }
                                    }
                                    // TODO make tabs identifiable, and make animation
                                    tm.tabs.remove(at: index)
                                },
                                tab: tm.tabs[index]
                            )
                            .padding(.leading, index == 0 ? 30 : 0)
                            .id(tm.tabs[index].id)
                            Divider().frame(height: 30).opacity(index == tm.tabs.count-1 ? 0 : 1)
                        }
                        Spacer()
                    }
                }
                .onChange(of: tm.tabs) { newTabs in
//                    if (newTabs.count > oldTabs.count) {
                        if let lastTab = newTabs.last {
                            proxy.scrollTo(lastTab.id)
                        }
//                    } 
                }
            }
//            Divider().opacity(tm.tabs.count > 0 ? 1 : 0)
            ZStack {
                ForEach(tm.tabs) { tab in
                    DetailTab(tab:tab)
//                        .padding(.vertical, 10)
//                        .background(Color.systemBackground)
                        .roundedCorner(10, corners: [.topLeft, .topRight])
//                        .padding(.horizontal, 0)
                        .opacity(tm.selected == tab ? 1 : 0)
                        .id(tab.id)
                        .padding(.horizontal, 10)
                        .onPreferenceChange(TabTitlePreferenceKey.self) { title in
                            guard !title.isEmpty else { return }
                            tm.selected?.navigationTitle = title
                            L.og.info("💄💄 onPreferenceChange: \(title)")
                        }
                }
                if (tm.tabs.count == 0) {
                    DiscoverNostr()
                }
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image("NosturLogoFull")
                            .resizable()
                            .opacity(!tm.tabs.isEmpty ? 0 : 0.3)
                            .frame(width: 400, height: 400)
                            .offset(x:offsetX, y:50)
                            .onAppear {
                                withAnimation(.easeOut(duration: 7.5)) {
                                    offsetX = 150
                                }
                            }
                    }
                }
            }
            .environmentObject(dim)
        }
        .navigationBarTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .padding(0)
        .background(Color("ListBackground"))
        .onReceive(receiveNotification(.navigateTo)) { notification in
            let destination = notification.object as! NavigationDestination
            if type(of: destination.destination) == NRPost.self {
                let p = destination.destination as! NRPost
                if p.kind == 30023 {
                    let tab = TabModel(articlePath: ArticlePath(id: p.id))
                    tm.tabs.append(tab)
                    tm.selected = tab
                    return
                }
                else {
                    let tab = TabModel(nrPost: p)
                    tm.tabs.append(tab)
                    tm.selected = tab
                    return
                }
            }
            else if type(of: destination.destination) == Event.self {
                let p = destination.destination as! Event
                let tab = TabModel(event: p)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == Naddr1Path.self {
                let p = destination.destination as! Naddr1Path
                let tab = TabModel(naddr1: p)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == ArticlePath.self {
                let p = destination.destination as! ArticlePath
                let tab = TabModel(articlePath: p)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == NotePath.self {
                let p = destination.destination as! NotePath
                let tab = TabModel(notePath: p)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == ContactPath.self {
                let c = destination.destination as! ContactPath
                let tab = TabModel(contactPath: c, profileTab:c.tab)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == Contact.self {
                let c = destination.destination as! Contact
                let tab = TabModel(contact: c)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            
        }
//        .onReceive(receiveNotification(.clearNavigation)) { notification in
//            tm.selected = nil
//            tm.tabs.removeAll()
//        }
    }
}

struct DetailPane_Previews: PreviewProvider {
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }, previewDevice: PreviewDevice(rawValue: "iPad Air (5th generation)")) {
            DetailPane()
                .onAppear {

                    if let event0 = PreviewFetcher.fetchNRPost() {
                        navigateTo(event0)
                    }

                    if let event1 = PreviewFetcher.fetchNRPost() {
                        navigateTo(event1)
                    }

                    if let event1 = PreviewFetcher.fetchNRPost() {
                        navigateTo(event1)
                    }
                    
                }
        }
    }
}
