//
//  TabbedDetailContainer.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2023.
//

import SwiftUI

final class DetailTabsModel: ObservableObject {
    
    static public let shared = DetailTabsModel()
    
    @Published var tabs:[Tab] = []
    @Published var selected:Tab? = nil
    
    struct Tab: Identifiable, Equatable {
        var id:UUID
        var notePath:NotePath?
        var contactPath:ContactPath?
        var event:Event?
        var nrPost:NRPost?
        var contact:Contact?
        
        init(notePath:NotePath? = nil, contactPath:ContactPath? = nil, event:Event? = nil, contact:Contact? = nil, nrPost:NRPost? = nil) {
            self.id = UUID()
            self.notePath = notePath
            self.contactPath = contactPath
            self.event = event
            self.contact = contact
            self.nrPost = nrPost
            
            if (contactPath != nil) {
                if let contactFromCache = Contact.fetchByPubkey(contactPath!.key, context: DataProvider.shared().container.viewContext) {
                    self.contact = contactFromCache
                }
            }
        }
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            return lhs.id == rhs.id
        }
    }
}

struct NosturTabButton: View {
    
    var isSelected:Bool = false
    var onSelect:() -> Void
    var onClose:() -> Void
    var label:String = "?"
    
    @State var isHoveringCloseButton = false
    @State var isHoveringTab = false
    
    var body: some View {
        HStack(spacing:5) {
            if IS_CATALYST {
                Image(systemName: "xmark")
                    .foregroundColor(isHoveringTab ? .gray : .clear)
                    .padding(4)
                    .contentShape(Rectangle())
                    .background(isHoveringCloseButton ? .gray.opacity(0.1) : .clear)
                    .onHover { over in
                        isHoveringCloseButton = over
                    }
                    .onTapGesture {
                        self.onClose()
                    }
            }
            else {
                Image(systemName: "xmark").foregroundColor(.gray)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.onClose()
                    }
            }
            Text(label)
                .lineLimit(1)
                .frame(maxWidth: 150)
        }
        .padding(.trailing, 23)
        .padding(.vertical, 10)
        .padding(.leading, 5)
        .background(isSelected ? Color.systemBackground : .clear)
        .contentShape(Rectangle())
        .onHover { over in
            isHoveringTab = over
        }
        .onTapGesture {
            self.onSelect()
        }
        .roundedCorner(10, corners: [.topLeft, .topRight])
    }
}

import UIKit

struct TabContainer: View {
    @State var navPath = NavigationPath()
    let tm:DetailTabsModel = .shared
    let tab:DetailTabsModel.Tab
    
    var body: some View {
        NavigationStack(path: $navPath) {
            if let nrPost = tab.nrPost {
                ZStack {
                    Color("ListBackground")
                        .ignoresSafeArea()
                    PostDetailView(nrPost: nrPost, navTitleHidden: true)
                }
////                    .padding()
////                              .background(Color.orange)
////                    .roundedCorner(10, corners: [.topLeft, .topRight])
////                    .padding(30)
////                    .background(.green)
////                    .padding(.top, 10)
                    .withNavigationDestinations()
            }
            else if let contact = tab.contact {
                VStack {
                    ProfileView(contact:contact)
                }
                    
            }
            else if let notePathId = tab.notePath?.id {
                NoteById(id: notePathId)//.opacity(tm.selected == tab ? 1 : 0)
            }
            else if let contacPubkey = tab.contactPath?.key {
                ProfileByPubkey(pubkey: contacPubkey)//.opacity(tm.selected == tab ? 1 : 0)
            }
            else {
                EmptyView()
            }
        }
        .onReceive(receiveNotification(.navigateTo)) { notification in
            guard tm.selected == tab else { return }
            let destination = notification.object as! NavigationDestination
            guard type(of: destination.destination) != HashtagPath.self else  { return }
            navPath.append(destination.destination)
        }
    }
}

struct TabbedDetailContainer: View {
    @StateObject private var dim = DIMENSIONS()
    @StateObject var tm = DetailTabsModel()
    @State var offsetX = 200.0
    
    func tabName(tab:DetailTabsModel.Tab) -> String {
        if let nrPost = tab.nrPost {
            return nrPost.anyName
        }
        if let event = tab.event {
            if let anyName = event.contact?.anyName {
                return anyName
            }
            else {
                return String(event.pubkey.suffix(11))
            }
        }
        if let contact = tab.contact {
            return contact.anyName
        }
        return "＿"
    }
    
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
                                isSelected: tm.selected == tm.tabs[safe: index],
                                onSelect: {
                                    guard let t = tm.tabs[safe: index] else { return }
                                    tm.selected = t
                                    if let nrPost = tm.selected?.nrPost {
                                        EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NosturTabButton.onSelect")
                                        req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "REALTIME-DETAIL"))
                                    }
                                }, onClose: {
                                    if (tm.selected == tm.tabs[safe: index]) {
                                        if (index != 0) {
                                            tm.selected = tm.tabs[safe: (index - 1)]
                                        }
                                        else if (tm.tabs.count > 1) {
                                            tm.selected = tm.tabs[1]
                                        }
                                        if let nrPost = tm.selected?.nrPost {
                                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NosturTabButton.onClose")
                                            req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "REALTIME-DETAIL"))
                                        }
                                        else {
                                            // Close REALTIME-DETAIL subscription if the new active tab is not a nrPost
                                            let closeMessage = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: "REALTIME-DETAIL"))
                                            SocketPool.shared.sendMessage(closeMessage)
                                        }
                                    }
                                    // TODO make tabs identifiable, and make animation
                                    tm.tabs.remove(at: index)
                                }, label: tm.tabs[safe: index] != nil ? "\(tabName(tab: tm.tabs[safe: index]!))" : "?")
                            .padding(.leading, index == 0 ? 30 : 0)
                            .id(tm.tabs[safe: index]?.id ?? UUID())
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
                    TabContainer(tab:tab)
//                        .padding(.vertical, 10)
//                        .background(Color.systemBackground)
                        .roundedCorner(10, corners: [.topLeft, .topRight])
//                        .padding(.horizontal, 0)
                        .opacity(tm.selected == tab ? 1 : 0)
                        .id(tab.id)
                        .padding(.horizontal, 10)
                }
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image("NosturLogoFull")
                            .resizable()
                            .opacity(tm.tabs.count > 0 ? 0 : 0.3)
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
//            Spacer()
        }
        .navigationBarTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .padding(0)
        .background(Color("ListBackground"))
        .onReceive(receiveNotification(.navigateTo)) { notification in
            let destination = notification.object as! NavigationDestination
            if type(of: destination.destination) == NRPost.self {
                let p = destination.destination as! NRPost
                let tab = DetailTabsModel.Tab(nrPost: p)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == Event.self {
                let p = destination.destination as! Event
                let tab = DetailTabsModel.Tab(event: p)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == NotePath.self {
                let p = destination.destination as! NotePath
                let tab = DetailTabsModel.Tab(notePath: p)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == ContactPath.self {
                let c = destination.destination as! ContactPath
                let tab = DetailTabsModel.Tab(contactPath: c)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == Contact.self {
                let c = destination.destination as! Contact
                let tab = DetailTabsModel.Tab(contact: c)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            
        }
        .onReceive(receiveNotification(.clearNavigation)) { notification in
            tm.selected = nil
            tm.tabs.removeAll()
        }
    }
}

struct TabbedDetailContainer_Previews: PreviewProvider {
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }, previewDevice: PreviewDevice(rawValue: "iPad Air (5th generation)")) {
            TabbedDetailContainer()
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



struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func roundedCorner(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners) )
    }
}
