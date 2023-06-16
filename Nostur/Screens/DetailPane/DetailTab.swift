import SwiftUI

struct DetailTab: View {
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
                        .withNavigationDestinations()
                }
            }
            else if let contact = tab.contact {
                ZStack {
                    Color("ListBackground")
                        .ignoresSafeArea()
                    ProfileView(contact:contact)
                        .withNavigationDestinations()
                }
            }
            else if let notePathId = tab.notePath?.id {
                ZStack {
                    Color("ListBackground")
                        .ignoresSafeArea()
                    NoteById(id: notePathId)//.opacity(tm.selected == tab ? 1 : 0)
                        .withNavigationDestinations()
                }
                
            }
            else if let contacPubkey = tab.contactPath?.key {
                ZStack {
                    Color("ListBackground")
                        .ignoresSafeArea()
                    ProfileByPubkey(pubkey: contacPubkey)//.opacity(tm.selected == tab ? 1 : 0)
                        .withNavigationDestinations()
                }
                
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

struct DetailTab_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadPosts() }, previewDevice: PreviewDevice(rawValue: "iPad Air (5th generation)")) {
            if let post = PreviewFetcher.fetchNRPost() {
                DetailTab(tab: DetailTabsModel.Tab(nrPost: post))
            }
        }
    }
}
