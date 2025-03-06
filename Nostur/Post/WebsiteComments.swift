//
//  WebsiteComments.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/01/2024.
//

import SwiftUI
import NostrEssentials

class WebsiteCommentsViewModel: ObservableObject {
    
    @Published var state: State = .initializing
    
    private var backlog: Backlog = Backlog(timeout: 8.0, auto: true)
    
    // STEP 1: FETCH ALL KIND:443's for this URL
    private func fetchKind443sFromRelays(url: String, onComplete: (() -> ())? = nil) {
        let reqTask = ReqTask(
            debounceTime: 0.1,
            reqCommand: { taskId in
                if let cm = NostrEssentials
                    .ClientMessage(
                        type: .REQ,
                        subscriptionId: taskId,
                        filters: [
                            Filters(
                                kinds: [443],
                                tagFilter: TagFilter(tag: "r", values: [url])
                            )
                        ]
                    ).json() {
                    req(cm)
                }
                else {
                    L.og.debug("Website Comments: Problem generating request")
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                self?.backlog.clear()
                self?.fetchKind443sFromDb(url: url, onComplete: onComplete)
                
                L.og.debug("Website Comments: ready to process relay response")
            },
            timeoutCommand: { [weak self] taskId in
                self?.backlog.clear()
                self?.fetchKind443sFromDb(url: url, onComplete: onComplete)
                L.og.debug("Website Comments: timeout ")
            })
        
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED POSTS FROM DB
    private func fetchKind443sFromDb(url: String, onComplete: (() -> ())? = nil) {
        bg().perform { [weak self] in
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "kind == 443 AND tagsSerialized CONTAINS %@", ###"["r",""###)
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            guard let events = try? bg().fetch(fr) else { return }
            
            let urlEvents = events.filter {  $0.fastTags.filter { $0.0 == "r" && $0.1 == url }.count > 0 }
            
            let roots: [NRPost] = urlEvents
                .map { NRPost(event: $0) }
                .sorted(by: { $0.createdAt > $1.createdAt })
            
            DispatchQueue.main.async {
                onComplete?()
                self?.state = .ready(roots)
            }
        }
    }
    
    public func load(url: String) {
        self.state = .loading
        self.fetchKind443sFromRelays(url: url)
    }
    
    public func timeout() {
        self.state = .timeout
    }
    
    public func error(_ message: String) {
        self.state = .error(message)
    }
    
    public enum State {
        case initializing
        case loading
        case ready([NRPost])
        case timeout
        case error(String)
    }
}

struct WebsiteComments: View {
    @EnvironmentObject private var themes: Themes
    public let nrPost: NRPost
    
    @StateObject private var vm = WebsiteCommentsViewModel()
    
    @ViewBuilder
    private var replyButton: some View {
        Image("ReplyIcon")
        Text("Add comment")
    }
    
    var body: some View {
        VStack {
            HStack(spacing: 0) {
                self.replyButton
                    .foregroundColor(themes.theme.footerButtons)
                    .padding(.leading, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        sendNotification(.createNewReply, ReplyTo(nrPost: nrPost))
                    }
                Spacer()
            }
            
            switch vm.state {
            case .initializing, .loading:
                ProgressView()
                    .onAppear {
                        if let url = nrPost.fastTags.first(where: { $0.0 == "r" })?.1 {
                            vm.load(url: url)
                        }
                        else {
                            vm.error("Failed to load.")
                        }
                    }
            case .ready(let roots):
                if !roots.isEmpty {
                    ForEach(roots) { root in
                        ThreadReplies(nrPost: root)
                            .id(root.id)
                    }
                }
                else {
                    Text("No comments found.")
                }
            case .timeout:
                Text("Time out")
            case .error(let errorMessage):
                Text(errorMessage)
                
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.parseMessages([
            ###"["EVENT", "root1", {"id":"7d56ff8134fa6e500776c2d0dce1e26131f859f352a390d2dd96303458821d82","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1704924199,"kind":443,"tags":[["r","https://nostur.com"]],"content":"Comments on https://nostur.com","sig":"c800110a4d0171e742f2bf3ab6f18392db4ba182df33d502dc6b5c582617b9f105ff6447305f8115de4657d8f6e171933921372375365e5292d84a555fd3a14d"}]"###,
            
            ###"["EVENT", "root2", {"id":"aaf06120c9683f7251a55f8a9686d09c9aa45411e3e73a021d25c352575e99b7","pubkey":"9c33d279c9a48af396cc159c844534e5f38e5d114667748a62fa33ffbc57b653","created_at":1704924199,"kind":443,"tags":[["r","https://nostur.com"]],"content":"Comments on https://nostur.com","sig":"c0c2d9f29cc106cce0126165b346d4014c6084426cdaa8c042759432eba93cb26ff008dd983c0dde9983dcd937bea07452300e81b972de133e1248821602d1a5"}]"###,
            
            
            ###"["EVENT", "replies", {"id":"1922cbd8baaadc89aa548fc51479437122dfa0540e1fa1a33b41eb99b54527c8","pubkey":"1d9c487f8c6d8306b994157d56e1a0b0a87abb2432c01fd3990926828d654474","created_at":1704952476,"kind":7,"tags":[["e","7d56ff8134fa6e500776c2d0dce1e26131f859f352a390d2dd96303458821d82"],["e","1923a0d439dee853e0cdbf85842ecfd6a9c67b7a5eb12b409dc55d683d00973d"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["p","3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"],["e","2f6cf057b3a23e26788b0a596881319b77bd2fa3246db249fb987500f3ce6b50"],["p","32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"]],"content":"🤙","sig":"d6b6ea204ea66d5855cfbd96f914878c8a49df3b86f1858c5f33b49b52f301e36ffbbea6e339cfcee89d1da2e251bd7459414b45e2170d3a06384b04950b8d0d"}"###,
            ###"["EVENT", "replies", {"id":"6d7dea44804c62660b32b6372b5a4d20dd2d136518c8ace90eabdd91c2e34f40","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1704933874,"kind":1,"tags":[["e","7d56ff8134fa6e500776c2d0dce1e26131f859f352a390d2dd96303458821d82","","root"],["e","2f6cf057b3a23e26788b0a596881319b77bd2fa3246db249fb987500f3ce6b50","","reply"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["p","3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"],["p","32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"],["client","Nostur","31990:9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33:1685868693432"]],"content":"I could only remember some nips with “r” as a reference to URL which is why I’m also using “r”. I looked at how nocomment works and it seems to post a kind:1 with a “r” url as root.\n\nWith this I want to create a “virtual” root, that is just the URL, the author should be hidden so it really looks like replies or comments on an URL and not someone replying to someone elses post.","sig":"75ff20131a692567f0b68efc0b9655f769d965a0295a5da32a57f586fbad9f06d8bd4b3210219a1a20f4823bf622e51581048ed53795d990d0b6637f04852a03"}"###,
            ###"["EVENT", "replies", {"id":"2f6cf057b3a23e26788b0a596881319b77bd2fa3246db249fb987500f3ce6b50","pubkey":"32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245","created_at":1704929738,"kind":1,"tags":[["e","7d56ff8134fa6e500776c2d0dce1e26131f859f352a390d2dd96303458821d82"],["e","1923a0d439dee853e0cdbf85842ecfd6a9c67b7a5eb12b409dc55d683d00973d"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["p","3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"]],"content":"nostr:npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6 came up with a way for kind1 comments to reference web pages (“r” tag). Not sure if this is the same thing you’re doing.","sig":"772b3dbba96b510ee356160e3c06413c5371673c480291ecbf23f89781d691214003189d467be3dbb7e34cc515d6e06e39b45368b4b0b834d1898626ae19c75d"}"###,
            ###"["EVENT", "replies", {"id":"1923a0d439dee853e0cdbf85842ecfd6a9c67b7a5eb12b409dc55d683d00973d","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1704929454,"kind":1,"tags":[["e","7d56ff8134fa6e500776c2d0dce1e26131f859f352a390d2dd96303458821d82","","root"],["e","0188a2d692053598e5127083a623b581b1443b71c7e4557443dd7af5d0b52437","","reply"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["p","32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"],["client","Nostur","31990:9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33:1685868693432"]],"content":"oh? which one?","sig":"2c8d418c408f9bb42fce360d637e1d8bb6ca9d680098acb5153f9ebed850a4c7db03289dc2fb1ee6f6b496d170ead4e075cb9f550e87afc124891f416ef406da"}"###,
            ###"["EVENT", "replies", {"id":"0188a2d692053598e5127083a623b581b1443b71c7e4557443dd7af5d0b52437","pubkey":"32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245","created_at":1704929420,"kind":1,"tags":[["e","7d56ff8134fa6e500776c2d0dce1e26131f859f352a390d2dd96303458821d82"],["e","c8b233ad67feff9786dc831394397a4a3e4bcb285d89f8deb51994fadeaf92fb"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"Isnt this a nip already","sig":"d7dfc636214b5b2fb5c47f682fd7dd899aa2f2d1d348d4a56c34df5b1b5547bac6eadda30a6a6e480b0a219fd666df5d173459c069f8bd32adbf226c3f054a15"}"###,
            ###"["EVENT", "replies", {"id":"c8b233ad67feff9786dc831394397a4a3e4bcb285d89f8deb51994fadeaf92fb","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1704929201,"kind":1,"tags":[["e","7d56ff8134fa6e500776c2d0dce1e26131f859f352a390d2dd96303458821d82","","root"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["client","Nostur","31990:9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33:1685868693432"]],"content":"Test post for https://github.com/nostur-com/nids/blob/main/02.md","sig":"1b1751abdd886b1a42dd4e78aabc27aae5c78067d248f82443ab5eb79ba9116516724db7e9d4ad294e5c6442d72a1fd1b6679c0fbcc92b8a9983983e6feb1dd1"}"###,
        ])
    }){
        if let kind443 = PreviewFetcher.fetchNRPost("7d56ff8134fa6e500776c2d0dce1e26131f859f352a390d2dd96303458821d82") {
            WebsiteComments(nrPost: kind443)
        }
    }
}
