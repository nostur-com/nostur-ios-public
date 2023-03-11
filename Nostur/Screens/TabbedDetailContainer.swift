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
        var contact:Contact?
        
        init(notePath:NotePath? = nil, contactPath:ContactPath? = nil, event:Event? = nil, contact:Contact? = nil) {
            self.id = UUID()
            self.notePath = notePath
            self.contactPath = contactPath
            self.event = event
            self.contact = contact
            
            if (contactPath != nil) {
                if let contactFromCache = Contact.fetchByPubkey(contactPath!.key, context: EventsProvider.shared.container.viewContext) {
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
            Image(systemName: "xmark").foregroundColor(isHoveringTab ? .gray : .clear)
                .padding(2)
                .background(isHoveringCloseButton ? .gray.opacity(0.1) : .clear)
                .onHover { over in
                    isHoveringCloseButton = over
                }
                .onTapGesture {
                    self.onClose()
                }
            Text(label)
        }
        .padding(.trailing, 23)
        .padding(.vertical, 5)
        .padding(.leading, 5)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .onHover { over in
            isHoveringTab = over
        }
        .onTapGesture {
            self.onSelect()
        }
    }
}

struct TabContainer: View {
    @State var path = NavigationPath()
    @StateObject var nav = NavigationModel(modelType: "TAB")
    
    var event:Event
    var body: some View {
        NavigationStack(path: $nav.tabPath) {
            NoteDetail(event: event, navTitleHidden:true)
                .withNavigationDestinations()
                .environmentObject(nav)
        }
    }
}

struct TabbedDetailContainer: View {
    
    @EnvironmentObject var tm:DetailTabsModel
    @State var offsetX = 200.0
    
    var body: some View {
        
        VStack(spacing:0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing:0) {
                    ForEach(tm.tabs.indices, id:\.self) { index in
                        NosturTabButton(
                            isSelected: tm.selected == tm.tabs[index],
                            onSelect: {
                                tm.selected = tm.tabs[index]
                            }, onClose: {
                                if (tm.selected == tm.tabs[index]) {
                                    if (index != 0) {
                                        tm.selected = tm.tabs[index - 1]
                                    }
                                }
                                tm.tabs.remove(at: index)
                            }, label: "\(tm.tabs[index].event?.name ?? tm.tabs[index].contact?.authorName ?? "...")")
                        
                        Divider().frame(height: 30).opacity(index == tm.tabs.count-1 ? 0 : 1)
                    }
                    Spacer()
                }
            }
            Divider().opacity(tm.tabs.count > 0 ? 1 : 0)
            ZStack {
                VStack{
                    Spacer()
                    HStack {
                        Spacer()
                        Image("NosturLogoFull")
                            .resizable()
                            .opacity(0.3)
                            .frame(width: 400, height: 400)
                            .offset(x:offsetX, y:50)
                            .onAppear {
                                withAnimation(.easeOut(duration: 7.5)) {
                                    offsetX = 150
                                }
                            }
                    }
                }
                ForEach(tm.tabs) { tab in
                    if (tab.event != nil) {
                        TabContainer(event: tab.event!)
                        .opacity(tm.selected == tab ? 1 : 0)
                        .id(tab.event!.id)
                    }
                    else if (tab.contact != nil) {
                        Profile(contact: tab.contact!).opacity(tm.selected == tab ? 1 : 0)
                    }
                    else if (tab.notePath != nil) {
                        NoteById(id: tab.notePath!.id).opacity(tm.selected == tab ? 1 : 0)
                    }
                    else if (tab.contactPath != nil) {
                        ProfileByPubkey(pubkey: tab.contactPath!.key).opacity(tm.selected == tab ? 1 : 0)
                    }
                    else {
                        EmptyView()
                    }
                }
            }
            Spacer()
            
//            Button {
//                if (tm.selected != nil) {
//                    tm.tabs.remove(at: tm.tabs.firstIndex(of: tm.selected!)!)
//                }
//            } label: { Text(" ") }
//                .keyboardShortcut("w")
//                .opacity(0)
        }
        .navigationBarTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .padding(0)
        .onAppear {
//            print(tm.tabs)
        }
        .onChange(of: tm.tabs) { newValue in
//            print(newValue)
        }
    }
}

struct TabbedDetailContainer_Previews: PreviewProvider {
    
    static var nav:NavigationModel = .shared
    
    static var previews: some View {
        TabbedDetailContainer()
            .onAppear {
                if let event0 = PreviewFetcher.fetchEvent("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3") {
                    nav.navigateTo(event0)
                }
                
                if let event1 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0") {
                    nav.navigateTo(event1)
                }
                
            }
            .withPreviewEnvironment()
    }
}
