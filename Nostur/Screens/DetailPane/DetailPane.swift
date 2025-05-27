//
//  DetailPane.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2023.
//

import SwiftUI
import UIKit
import NavigationBackport
import NostrEssentials

struct DetailPane: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @StateObject private var tm = DetailTabsModel()
    @State private var offsetX = 200.0

    init() {
//        UIScrollView.appearance().bounces = false
    }
    
    var body: some View {
        
        VStack(spacing:0) {
            Color.clear.frame(height: 0)
                .modifier(SizeModifier())
                .onPreferenceChange(SizePreferenceKey.self) { size in
                    guard size.width > 0 else { return }
                    dim.listWidth = size.width
                }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing:0) {
                        ForEach(tm.tabs.indices, id:\.self) { index in
                            // TODO: Clean up / Refactor below:
                            NosturTabButton(
                                isSelected: tm.selected == tm.tabs[index],
                                onSelect: {
                                    guard index < tm.tabs.count else { return }
                                    let t = tm.tabs[index]
                                    tm.selected = t
                                    t.suspended = false
                                    if let nrPost = tm.selected?.nrPost {
                                        bg().perform {
                                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NosturTabButton.onSelect")
                                        }
                                        if nrPost.kind >= 30000 && nrPost.kind < 40000 {
                                            req(RM.getPREventReferences(aTag: nrPost.aTag, subscriptionId: "REALTIME-DETAIL"))
                                        }
                                        else {
                                            req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "REALTIME-DETAIL"))
                                        }
                                    }
                                    else if let notePath = tm.selected?.notePath {
                                        req(RM.getEventReferences(ids: [notePath.id], subscriptionId: "REALTIME-DETAIL"))
                                    }
                                    else if let event = tm.selected?.event {
                                        bg().perform {
                                            EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NosturTabButton.onSelect.2")
                                            req(RM.getEventReferences(ids: [event.id], subscriptionId: "REALTIME-DETAIL"))
                                        }
                                    }
                                    else if let naddrPath = tm.selected?.naddr1 {
                                        if naddrPath.kind == 30311 {
                                            if let cm = NostrEssentials
                                                .ClientMessage(type: .REQ,
                                                               subscriptionId: "REALTIME-DETAIL",
                                                               filters: [
                                                                Filters(
                                                                    authors: [naddrPath.pubkey],
                                                                    kinds: [30311],
                                                                    tagFilter: TagFilter(tag: "d", values: [naddrPath.dTag]),
                                                                    limit: 1
                                                                )
                                                               ]
                                                ).json() {
                                                req(cm)
                                            }
                                        }
                                        else if naddrPath.kind >= 30000 && naddrPath.kind < 40000 {
                                            req(RM.getPREventReferences(aTag: naddrPath.navId, subscriptionId: "REALTIME-DETAIL"))
                                        }
                                        else {
                                            req(RM.getEventReferences(ids: [naddrPath.id], subscriptionId: "REALTIME-DETAIL"))
                                        }
                                    }
                                },
                                onClose: {
                                    if (index < tm.tabs.count && tm.selected == tm.tabs[index]) {
                                        if (index != 0) {
                                            tm.selected = tm.tabs[(index - 1)]
                                            tm.selected?.suspended = false
                                            if let id = tm.selected?.id {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                    proxy.scrollTo(id)
                                                }
                                            }
                                        }
                                        else if (tm.tabs.count > 1) {
                                            tm.selected = tm.tabs[1]
                                            tm.selected?.suspended = false
                                            if let id = tm.selected?.id {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                    proxy.scrollTo(id)
                                                }
                                            }
                                        }
                                        if let nrPost = tm.selected?.nrPost, tm.tabs.count > 1  {
                                            bg().perform {
                                                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NosturTabButton.onClose")
                                            }
                                            if nrPost.kind == 30311 {
                                                if let cm = NostrEssentials
                                                    .ClientMessage(type: .REQ,
                                                                   subscriptionId: "REALTIME-DETAIL",
                                                                   filters: [
                                                                    Filters(
                                                                        authors: [nrPost.pubkey],
                                                                        kinds: [30311],
                                                                        tagFilter: TagFilter(tag: "d", values: [nrPost.dTag ?? ""]),
                                                                        limit: 1
                                                                    )
                                                                   ]
                                                    ).json() {
                                                    req(cm)
                                                }
                                            }
                                            else if nrPost.kind >= 30000 && nrPost.kind < 40000 {
                                                req(RM.getPREventReferences(aTag: nrPost.aTag, subscriptionId: "REALTIME-DETAIL"))
                                            }
                                            else {
                                                req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "REALTIME-DETAIL"))
                                            }
                                        }
                                        else if let notePath = tm.selected?.notePath {
                                            req(RM.getEventReferences(ids: [notePath.id], subscriptionId: "REALTIME-DETAIL"))
                                        }
                                        else if let event = tm.selected?.event {
                                            bg().perform {
                                                EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NosturTabButton.onSelect.2")
                                                req(RM.getEventReferences(ids: [event.id], subscriptionId: "REALTIME-DETAIL"))
                                            }
                                        }
                                        else if let naddrPath = tm.selected?.naddr1 {
                                            if naddrPath.kind == 30311 {
                                                if let cm = NostrEssentials
                                                    .ClientMessage(type: .REQ,
                                                                   subscriptionId: "REALTIME-DETAIL",
                                                                   filters: [
                                                                    Filters(
                                                                        authors: [naddrPath.pubkey],
                                                                        kinds: Set([30311]),
                                                                        tagFilter: TagFilter(tag: "d", values: [naddrPath.dTag]),
                                                                        limit: 1
                                                                    )
                                                                   ]
                                                    ).json() {
                                                    req(cm)
                                                }
                                            }
                                            else if naddrPath.kind >= 30000 && naddrPath.kind < 40000 {
                                                req(RM.getPREventReferences(aTag: naddrPath.navId, subscriptionId: "REALTIME-DETAIL"))
                                            }
                                            else {
                                                req(RM.getEventReferences(ids: [naddrPath.id], subscriptionId: "REALTIME-DETAIL"))
                                            }
                                        }
                                        else {
                                            // Close REALTIME-DETAIL subscription if the new active tab is not a nrPost
                                            ConnectionPool.shared.sendMessage(
                                                NosturClientMessage(
                                                    clientMessage: NostrEssentials.ClientMessage(
                                                        type: .CLOSE,
                                                        subscriptionId: "REALTIME-DETAIL"
                                                    ),
                                                    relayType: .READ
                                                )
                                            )
                                        }
                                    }
                                    // TODO make tabs identifiable, and make animation
                                    if index < tm.tabs.count {
                                        let closedTab = tm.tabs[index]
                                        if closedTab.navId == LiveKitVoiceSession.shared.currentRoomATag {
                                            LiveKitVoiceSession.shared.disconnect()
                                        }
                                        else if let nrLiveEvent = closedTab.nrLiveEvent, LiveKitVoiceSession.shared.currentRoomATag == nrLiveEvent.id  {
                                            LiveKitVoiceSession.shared.disconnect()
                                        }
                                        else if let nrPost = closedTab.nrPost, nrPost.kind == 30311, LiveKitVoiceSession.shared.currentRoomATag == nrPost.aTag {
                                            LiveKitVoiceSession.shared.disconnect()
                                        }
                                        else if let naddrPath = closedTab.naddr1, naddrPath.kind == 30311, LiveKitVoiceSession.shared.currentRoomATag == naddrPath.navId {
                                            LiveKitVoiceSession.shared.disconnect()
                                        }
                                    }
                                    tm.tabs.remove(at: index)
                                },
                                tab: tm.tabs[index]
                            )
                            .padding(.leading, index == 0 ? 30 : 0)
                            .id(tm.tabs[index].id)
                            themes.theme.background
                                .frame(width: 1.0, height: 30)
                                .overlay {
                                    themes.theme.listBackground
                                        .frame(width: 1.0, height: 20)
                                }
                                .opacity(index == tm.tabs.count-1 ? 0 : 1)
                        }
                        Spacer()
                    }
                }
                .onChange(of: tm.tabs) { newTabs in
                    if let lastTab = newTabs.last {
                        proxy.scrollTo(lastTab.id)
                    }
                }
                .background(themes.theme.background)
            }

            ZStack {
                ForEach(tm.tabs) { tab in
                    if !tab.suspended {
                        DetailTab(tab: tab)
                            .environmentObject(dim)
                            .environmentObject(tm)
                            .opacity(tm.selected == tab ? 1 : 0)
                            .id(tab.id)
                            .onPreferenceChange(TabTitlePreferenceKey.self) { title in
                                guard !title.isEmpty else { return }
                                tm.selected?.navigationTitle = title
                                L.og.debug("💄💄 onPreferenceChange: \(title)")
                            }
                    }
                    else {
                        ProgressView()
                            .opacity(tm.selected == tab ? 1 : 0)
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
        }
        .navigationBarTitle("")
        .navigationBarTitleDisplayMode(.inline)

        .background(themes.theme.listBackground)
        .onReceive(receiveNotification(.navigateTo)) { notification in
            // This does similar as .withNavigationDestinations() but for DetailPane, should refactor / clean up
            let destination = notification.object as! NavigationDestination
            
            // Navigating from the main feed ("Default") open a new tab in the DetailPane
            // Navigating from inside the DetailPanel will have context "DetailPane", should not create new tab, but navigate inside existing tab
            guard destination.context == "Default" else { return }
            
            let navId = destination.destination.id as! String
            
            if let existingTab = tm.tabs.first(where: { $0.navId == navId }) {
                tm.selected = existingTab
                tm.selected?.suspended = false
                return
            }
            
            if type(of: destination.destination) == NRPost.self {
                let p = destination.destination as! NRPost
                if p.kind == 30023 {
                    let tab = TabModel(articlePath: ArticlePath(id: p.id), navId: p.id)
                    tm.tabs.append(tab)
                    tm.selected = tab
                    return
                }
                else {
                    let tab = TabModel(nrPost: p, navId: p.id)
                    tm.tabs.append(tab)
                    tm.selected = tab
                    return
                }
            }
            else if type(of: destination.destination) == NRLiveEvent.self {
                let p = destination.destination as! NRLiveEvent
                let tab = TabModel(nrLiveEvent: p, navId: p.id)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == Event.self {
                let p = destination.destination as! Event
                let tab = TabModel(event: p, navId: p.id)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == Naddr1Path.self {
                let p = destination.destination as! Naddr1Path
                
                if let existingTab = tm.tabs.first(where: { $0.navId == p.navId }) {
                    tm.selected = existingTab
                    tm.selected?.suspended = false
                    return
                }
                
                let tab = TabModel(naddr1: p, navId: p.navId)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == ArticlePath.self {
                let p = destination.destination as! ArticlePath
                let tab = TabModel(articlePath: p, navId: p.id)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == NotePath.self {
                let p = destination.destination as! NotePath
                let tab = TabModel(notePath: p, navId: p.id)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == ContactPath.self {
                let c = destination.destination as! ContactPath
                let tab = TabModel(contactPath: c, profileTab:c.tab, navId: c.id)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }     
            else if type(of: destination.destination) == NRContactPath.self {
                let c = destination.destination as! NRContactPath
                let tab = TabModel(nrContactPath: c, profileTab:c.tab, navId: c.id)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            else if type(of: destination.destination) == NRContact.self {
                let c = destination.destination as! NRContact 
                let tab = TabModel(nrContact: c, navId: c.pubkey)
                tm.tabs.append(tab)
                tm.selected = tab
                return
            }
            
        }
        .onReceive(receiveNotification(.navigateToOnDetail)) { notification in
            // For now, for opening the Gallery on Detail Pane. Could use for other things too
            let destination = notification.object as! NavigationDestination

            if type(of: destination.destination) == ViewPath.self {
                let viewPath = destination.destination as! ViewPath
                switch viewPath {
                    case .Gallery(let galleryVM):
                    
                    let tab = TabModel(galleryVM: galleryVM, navId: "Gallery")
                    tm.tabs.append(tab)
                    tm.selected = tab
                    default:
                        break
                }
            }            
        }
        .onChange(of: tm.tabs) { _ in
            tm.saveTabs()
        }
        .onAppear {
            tm.restoreTabs()
        }
        .onReceive(receiveNotification(.unpublishedNRPost)) { notification in
            
            // On Undo send, if we have our post open in a tab it needs to be removed
        
            let nrPost = notification.object as! NRPost
            if let index = tm.tabs.firstIndex(where: { nrPost.id == $0.nrPost?.id }) {
                // Copy pasta from onClose above:
                if (index < tm.tabs.count && tm.selected == tm.tabs[index]) {
                    if (index != 0) {
                        tm.selected = tm.tabs[(index - 1)]
                        tm.selected?.suspended = false
                        
                    }
                    else if (tm.tabs.count > 1) {
                        tm.selected = tm.tabs[1]
                        tm.selected?.suspended = false
                       
                    }
                    if let nrPost = tm.selected?.nrPost, tm.tabs.count > 1  {
                        bg().perform {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NosturTabButton.onClose")
                        }
                        if nrPost.kind == 30023 {
                            req(RM.getPREventReferences(aTag: nrPost.aTag, subscriptionId: "REALTIME-DETAIL"))
                        }
                        else {
                            req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "REALTIME-DETAIL"))
                        }
                    }
                    else {
                        // Close REALTIME-DETAIL subscription if the new active tab is not a nrPost
                        ConnectionPool.shared.sendMessage(
                            NosturClientMessage(
                                clientMessage: NostrEssentials.ClientMessage(
                                    type: .CLOSE,
                                    subscriptionId: "REALTIME-DETAIL"
                                ),
                                relayType: .READ
                            )
                        )
                    }
                }
                tm.tabs.remove(at: index)
            }
        }
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
                        navigateTo(event0, context: "DetailPane")
                    }

                    if let event1 = PreviewFetcher.fetchNRPost() {
                        navigateTo(event1, context: "DetailPane")
                    }

                    if let event1 = PreviewFetcher.fetchNRPost() {
                        navigateTo(event1, context: "DetailPane")
                    }
                    
                }
        }
    }
}



struct DetailPane2_Previews: PreviewProvider {
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadRepliesAndReactions()
        }, previewDevice: PreviewDevice(rawValue: "iPad Air (5th generation)")) {
            NBNavigationStack {
                if let matt = PreviewFetcher.fetchNRPost("e593fc759291a691cd0127643a0b9fac9d92613952845e207eb24332937c59d9") {
                    
                    PostDetailView(nrPost: matt)
                }
            }
        }
    }
}


struct DetailPane3_Previews: PreviewProvider {
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadRepliesAndReactions()
        }, previewDevice: PreviewDevice(rawValue: "iPad Air (5th generation)")) {
            NBNavigationStack {
                if let matt = PreviewFetcher.fetchNRPost("b083d13550aa7ec88d6be15eb7a518df14e9f86ffec3e314c30b84ea4156f381") {
                    
                    PostDetailView(nrPost: matt)
                }
            }
        }
    }
}

struct DuplicateRepliesTest_Previews: PreviewProvider {
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.parseMessages([
                ###"["EVENT","CONTACT",{"pubkey":"efc37e97fa4fad679e464b7a6184009b7cc7605aceb0c5f56b464d2b986a60f0","content":"{\"banner\":\"https://nostr.build/i/8fc6f2f739dffdc92aca6bd27c0a62a796aad17d5d335d1ed3adfe37936f89af.gif\",\"website\":\"https://jingles.dev\",\"lud06\":\"LNURL1DP68GURN8GHJ7EM9W3SKCCNE9E3K7MF0D3H82UNVWQHK56TWVAKX2UMRDAJX2VANDPK\",\"nip05\":\"_@jingles.dev\",\"picture\":\"https://jingles.dev/images/profile.jpg\",\"display_name\":\"Jingles\",\"about\":\"Building on #NOSTR\\nApplying #AI in #neuroscience\\n\\nVault\\nfree, open source, and decentralized password manager\\nhttps://github.com/jinglescode/nostr-password-manager\\n\\nW3\\nfree URL shortener service for everyone\\nhttps://w3.do\\n\\nNDK\\nlibrary that makes it easy to build NOSTR apps\\nhttps://ndk-react-demo.vercel.app/\",\"name\":\"jingles\"}","id":"f91bfc37fe82df51397d84a6443c0a6f94c8bfdf73f9a09db161f88f075e732c","created_at":1692263373,"sig":"69ebed36d901be9825dd9a5606fb13c1e6fde7c5380c5fe8c321dd049be80690f4eb2a47597f07eed12d3e9775b33f674bc12ab7e672527080a2e5ee1c93d8a8","kind":0,"tags":[]}]"###,
                ###"["EVENT","ROOT",{"pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","content":"Querying relays for hashtags is case-sensitive?\n\n#AskNostr #asknostr #Asknostr","id":"79ce4e9090f52bad274d06ff784f49124da422813dc018a551736e793b69268a","created_at":1692678017,"sig":"18b7bb2d3fd6ee9859c2f7d59ab7b7adc1a46c4057463ad3048a70bfb145ca81932fbb7d940c7dcfedb39436e820037860ee66e7262074b2ca5d6c3954fcd079","kind":1,"tags":[["t","AskNostr"],["t","asknostr"],["t","Asknostr"]]}]"###,
                ###"["EVENT","REPLY1",{"pubkey":"efc37e97fa4fad679e464b7a6184009b7cc7605aceb0c5f56b464d2b986a60f0","content":"From my testing in the past, it’s not case sensitive. \n\nA good test case is #btc.","id":"99361112e7a6b1bf7aebce5703a797d3e120c32bff5178048ca7891093572319","created_at":1692678666,"sig":"cd598272f28159d1e4d0251226d6fd336612e691a16b3fac1fee1deb06a0957c6614862711c06666e407a1c84cf3cbd37e39c0c96171128b2774354ee3f78d3b","kind":1,"tags":[["e","79ce4e9090f52bad274d06ff784f49124da422813dc018a551736e793b69268a"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["t","btc"]]}]"###,
                ###"["EVENT","REPLY1.1",{"pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","content":"Can't find your post when querying for ‘BTC’\n\nMaybe some clients are overloading tags with all variants so it gets found by any query","id":"a976eda2dac1f509cb82e85ccd8947b3f84e68da2e7536e17e04b9d7ced7eb29","created_at":1692679584,"sig":"7032615964b10e971782b358ea12a31a565476019cc2eb50ae26e7f066cbc52b586c16772ebd5e3e7d7b21ae460205f21705dd04ece5b78f5e6065e6e983c920","kind":1,"tags":[["e","79ce4e9090f52bad274d06ff784f49124da422813dc018a551736e793b69268a","","root"],["e","99361112e7a6b1bf7aebce5703a797d3e120c32bff5178048ca7891093572319","","reply"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["p","efc37e97fa4fad679e464b7a6184009b7cc7605aceb0c5f56b464d2b986a60f0"]]}]"###,
                ###"["EVENT","REPLY1.1.1",{"pubkey":"efc37e97fa4fad679e464b7a6184009b7cc7605aceb0c5f56b464d2b986a60f0","content":"Hmm.? That’s different from what i remembered. \nLet you know if I see anything later.","id":"0944f3733fbfd83674943a32c6b54edd719f1ce29c8a7f0427be43a6c3c7ff3a","created_at":1692679915,"sig":"1d152ce682929aae4858b3157fe57af6788810cd745ce2e22bed3e87040bac470b936da0663a3ed5f3ccf8ef88f768c30be31465131aa93bc6e3062ecfcb7f79","kind":1,"tags":[["e","79ce4e9090f52bad274d06ff784f49124da422813dc018a551736e793b69268a",""],["e","a976eda2dac1f509cb82e85ccd8947b3f84e68da2e7536e17e04b9d7ced7eb29"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]]}]"###
            ])
        }, previewDevice: PreviewDevice(rawValue: "iPad Air (5th generation)")) {
            NBNavigationStack {
                if let post = PreviewFetcher.fetchNRPost("79ce4e9090f52bad274d06ff784f49124da422813dc018a551736e793b69268a") {
                    
                    PostDetailView(nrPost: post)
                }
            }
        }
    }
}



