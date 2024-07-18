//
//  NRText.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/10/2023.
//

import SwiftUI
import RepresentableKit

struct NRTextDynamic: View {
    @EnvironmentObject private var themes: Themes
    
    private let attributedString: NSAttributedString
    private let plain: Bool
    private let fontColor: Color
    private let accentColor: Color?
    
    init(_ attributedString: NSAttributedString, plain: Bool = false, fontColor: Color = Themes.default.theme.primary, accentColor: Color? = nil) {
        self.attributedString = attributedString
        self.plain = plain
        self.fontColor = fontColor
        self.accentColor = accentColor
    }
    
    init(_ text: String, plain: Bool = false, fontColor: Color = Themes.default.theme.primary, accentColor: Color? = nil) {
        self.fontColor = fontColor
        self.accentColor = accentColor
        do {
            let mutableAttributedString = try NSMutableAttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
                        
            let attributes:[NSAttributedString.Key: NSObject] = [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor(self.fontColor)
            ]
            
            mutableAttributedString.addAttributes(
                attributes,
                range: NSRange(location: 0, length: mutableAttributedString.length)
            )
            
            mutableAttributedString.addHashtagIcons()
            
            self.attributedString = NSAttributedString(attributedString: mutableAttributedString)
        }
        catch {
            let mutableAttributedString = NSMutableAttributedString(string: text)
            let attributes:[NSAttributedString.Key: NSObject] = [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor(self.fontColor)
            ]
            
            mutableAttributedString.addAttributes(
                attributes,
                range: NSRange(location: 0, length: mutableAttributedString.length)
            )
            
            mutableAttributedString.addHashtagIcons()
            
            L.og.error("NRTextParser: \(error)")
            self.attributedString = NSAttributedString(attributedString: mutableAttributedString)
        }
        self.plain = plain
    }
    
    var body: some View {
        UIViewAdaptor {
            makeUITextView()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    func makeUITextView() -> UITextView {
        let view = UITextView()
//        _ = view.layoutManager
        view.isScrollEnabled = false
        view.textColor = UIColor(self.fontColor)
        view.tintColor = UIColor(accentColor ?? themes.theme.accent)
        view.isSelectable = true
        view.isEditable = false
        view.dataDetectorTypes = plain ? [] : [.link]
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        
        view.attributedText = attributedString
        
        return view
    }
}

#Preview("NRTextDynamic") {
    VStack {
        Text("[#bitcoin](nostur:t:bitcoin)")
        let what = NRTextParser.replaceHashtagsWithMarkdownLinks(in: "Trying out some #nostr hashtags for the next update of #Nostur.\n\n#Zaps #Bitcoin")
        let _ = print(what)
        NRTextDynamic(what)
            .background(Color.red)
        Spacer()
        NRTextDynamic("Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long")
            .background(Color.blue)
        
        Text("What")
            .background(Color.green)
    }
    .padding()
    .environmentObject(Themes.default)
    .environmentObject(DIMENSIONS())
}


#Preview("Long post, truncating") {
    PreviewContainer({ pe in
        pe.parseMessages([
            ###"["EVENT", "long", {"pubkey":"2edbcea694d164629854a52583458fd6d965b161e3c48b57d3aff01940558884","content":"THE NOSTR REPORT\n\nSAVE BITCOIN, SPEND BITCOIN\nOct 25, 2023\nBlock Height: 813,777\nMoscow Time: 29:03 ⚡/ $\nV4V: 10 zaps ⚡ 22,800\nTop Zapper: nostr:npub1jg552aulj07skd6e7y2hu0vl5g8nl5jvfw8jhn6jpjk0vjd0waksvl6n8n  (⚡21,000)\nNostr Report is committed to V4V, thank you to our supporters.\n—--------------------------\n🎙️Quote of the Day🎙️\n—--------------------------\n“Saving bitcoin changes your life. Spending bitcoin changes the world.”\nnostr:npub1marcan0laywmjprf4m8d34dr8m724a6jxxa56a5wwygcgj23q7nskfwmfg \nnostr:note1jzv3cpugrtngce3j45zssyzdvhu4szndwp57h3qjc5cd6lrcwqpqrdr0mt\n—--------------------------\n🚨Headline Nostr News🚨\n—--------------------------\nnostr:npub1hqaz3dlyuhfqhktqchawke39l92jj9nt30dsgh2zvd9z7dv3j3gqpkt56s Join Avi and QW for a special mid-week episode of Plebchain Radio, featuring conference organizer extraordinaire Mcshane! Tune in and get a sneak peek at all the excitement coming up at Nostrasia. Today at 8pm ET (9am Tokyo time, and UTC -4). https://nostrnests.com/plebchainradio\nnostr:note17xwuv9veym70esj3j95757psv3mvea2j93jmkc9hjars2l8p6jjqt59t6d\n\nnostr:npub17tlh448s3tfdfgymehqdkdn52as59qsrax0n9h58pk54wcmqyc2qklzsxj Postmortem on the lightning cycling replacement attack vulnerability, by Shinobi. “This is a legitimate vulnerability in the Lightning protocol, but the sky is not falling.” Link to full article in note.\nnostr:note1523jhq3nucl6y8g49aha5dxmv4mau9fuyem72h5g409xvwkshshqpzyl6z\n\nnostr:npub1qny3tkh0acurzla8x3zy4nhrjz5zd8l9sy9jys09umwng00manysew95gx announces Citadel Dispatch today at 1pm ET (1700 UTC) will feature Evan Kaloudis to discuss all things nostr:npub1xnf02f60r9v0e5kty33a404dm79zr7z2eepyrk5gsq3m7pwvsz2sazlpr5 https://citadeldispatch.com/stream \nnostr:note1dwutq2m9457vphtad6nznlk646ee3c5nsvs3z2z0ysdnssmtq2kq00tvuw\n\nnostr:npub1u8lnhlw5usp3t9vmpz60ejpyt649z33hu82wc2hpv6m5xdqmuxhs46turz New ZapplePay update brings AutoZaps. Like a decentralized Patreon, AutoZaps uses NWC and allows you to subscribe to any account to support them with recurring zaps.\nnostr:note1hpd5s3snyv72fqqnpet2ef8cxgngatrewcdaswxetzrzguuqpg2qjstce9\n\nnostr:npub1563z6kxmvuy7s8zhzan8m0hzmkavyfzg2aw6h7f0fvcvdms398csaxc9n6 makes their presence (and intentions) known on Nostr. Welcome 👀\nnostr:note1kufex8d3u3qm7c8lzyknl98lyp20y452m5snrcxaanza9swh536qky30sh\n\nnostr:npub1nstrcu63lzpjkz94djajuz2evrgu2psd66cwgc0gz0c0qazezx0q9urg5l Make sure to join the #Nostrasia community group for virtual and in-person attendees.\nnostr:note1uu6zjs653wq7353umaust3w29emcenddktjffxyz5qqahfp370hq6tsqfx\n\nnostr:npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m shows us his #Bitkey beta 🪨\nnostr:note1uyajs53a8m5fehxu9jjhf5qqmrn9uqfaffgl8dalmg68eu8jkxasnj7ppm\n\nnostr:npub1fpcd25q2zg09rp65fglxuhp0acws5qlphpg88un7mdcskygdvgyqfv4sld TPB58 - Bitcoin's Bullish Case for Humanity with nostr:npub1trr5r2nrpsk6xkjk5a7p6pfcryyt6yzsflwjmz6r7uj7lfkjxxtq78hdpu is out now.\nnostr:note1xv64psmukv7ktyfehnsqdkjy5u3nq5nffrvr7fj9mwlg40jauqdsfch9u9\n\nnostr:npub1mlcas7pe55hrnlaxd7trz0u3kzrnf49vekwwe3ca0r7za2n3jcaqhz8jpa The latest episode of the #TGFNostrpod is out, featuring nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft discussing relay sets, gift wrap, scheduled notes, and more.\nnostr:note1yeh2wlds3mct5w3wsrtsvpw65jwy67xcujwhvnwdxe02lq5c7e3sl6anht\n—--------------------------\n💻nostr Tech💻\n—--------------------------\nnostr:npub1wj9l4p7yx7efg9jdz7ztxf9q6t55jhyzdrsqgn3uw7t28v2ce8vqnuhet9 is looking for help translating the client into additional languages.\nnostr:note17efgmkn6jeg2yd5t58tgd74ye48wzth2v5n7ku8thxkyg3x7lq9qh9mqt7\n\nnostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft shows a new zap subscription tool he’s been working on, which he will release today.\nnostr:note18dtapxye8reggjy7np7vwe5xazaf0rq43zw95u47yh7ylcwutjesl7muq3\n\nnostr:npub1ghzp7g0peac4lfkeegst3cqz546dk7a5n6twazvrf3nd432yddaqa3qtwq Flycat client updated to v0.2.6 includes fixes with article loading, as well as now hosting a simple NIP-05 service for the domain flycat.club.\nnostr:note1h5dyfsw29g605kaqh94kvc2309mflprmu288jzxjthnw285ukxxq3xgakq\n\nnostr:npub1t89vhkp66hz54kga4n635jwqdc977uc2crnuyddx7maznwfrpupqwra5h9 shares the latest episode of #Nostrovia to learn about the nostr:npub1h0rnetjp2qka44ayzyjcdh90gs3gzrtq4f94033heng6w34s0pzq2yfv0g project 🐝 Be sure to check it out.\nnostr:note1kwjpq66hxgfcz2w3hjrduahnllslknwtnzjh3dh87v89y7ddfrxsaccu7z\n\nnostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft asks for feedback: “If you had a way to preserve your Nostr identity so that you could recover from someone compromising your nsec and it required writing a note in your Nostr client, would you do it?”\nnostr:note1qmuakk7f6zr3h8x0ng7ryc8rw2f2vjdr2ka74ayvh4lxr4hrk3jswxuqcp\n\nnostr:npub1hxjnw53mhghumt590kgd3fmqme8jzwwflyxesmm50nnapmqdzu7swqagw3 LDK v0.0.118: BOLT12 Sending & Receiving\nnostr:note1ya782u0uxveawl5y20teu42vfeqcrqqgqf8jle6l6zjkrwe2txzsh4k5ky\n\nnostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft \nshowcases what3words, a very cool alternative to gps coordinates, check it out: https://w3w.co \nnostr:note17scjzxx2cym98r00rjhek4e0h32gkkphqxu4yxrlt3swujwrjc7qe39lcx\n—--------------------------\n⚡nostr Business⚡\n—--------------------------\nLet this piece by nostr:npub1qe3e5wrvnsgpggtkytxteaqfprz0rgxr8c3l34kk3a9t7e2l3acslezefe resonate with you while you read it. 💜\nnostr:note14qu7nkjrgn87m4rkrjwlwk5f03p4ldmkmm5hhf0r7t4hphxxmnyskaf23q\n\nnostr:npub1txwy7guqkrq6ngvtwft7zp70nekcknudagrvrryy2wxnz8ljk2xqz0yt4x Ministry of Nodes plug and play bitcoin node available for purchase, or learn to build your own. Info in linked note.\nnostr:note1s4reswg0eaja96nppuvlz8ck277uyf72cugteqgcsg05s0nccp6q2ujmwx\n—--------------------------\n🔥🔥Meme of the Day🔥🔥\n—--------------------------\nnostr:npub1dergggklka99wwrs92yz8wdjs952h2ux2ha2ed598ngwu9w7a6fsh9xzpc cause and effect\nnostr:note1p0lu555yj85m6ltck7j9a0nzq07qt7uq0ha0f0q6pjfspve0d9lqwj04yd\n—--------------------------\nStay Classy, Nostr.\nhttps://nostr.report","id":"a3d05222ad9459511b66814348eff9688f24edc06d1f86897636ae7c7bb2e031","created_at":1698239776,"sig":"6afcdfe82c54d7f93d761f60575cdb7bdbfcd76e73d7cfe7e248801b3c79c14776c61de7511fbc4deea8a72fff6e9237cb1d80a1201129857ce62a5c4e542c67","kind":1,"tags":[["p","922945779f93fd0b3759f1157e3d9fa20f3fd24c4b8f2bcf520cacf649af776d"],["p","df478ecdffe91db90469aeced8d5a33efcaaf75231bb4d768e711184495107a7"],["p","b83a28b7e4e5d20bd960c5faeb6625f95529166b8bdb045d42634a2f35919450"],["r","https://nostrnests.com/plebchainradio"],["p","f2ff7ad4f08ad2d4a09bcdc0db36745761428203e99f32de870da95763602614"],["p","04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9"],["p","34d2f5274f1958fcd2cb2463dabeaddf8a21f84ace4241da888023bf05cc8095"],["r","https://citadeldispatch.com/stream"],["p","e1ff3bfdd4e40315959b08b4fcc8245eaa514637e1d4ec2ae166b743341be1af"],["p","a6a22d58db6709e81c5717667dbee2ddbac22448575dabf92f4b30c6ee1129f1"],["p","9c163c7351f8832b08b56cbb2e095960d1c5060dd6b0e461e813f0f07459119e"],["t","nostrasia"],["p","82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"],["t","bitkey"],["p","4870d5500a121e5187544a3e6e5c2fee1d0a03e1b85073f27edb710b110d6208"],["p","58c741aa630c2da35a56a77c1d05381908bd10504fdd2d8b43f725efa6d23196"],["p","dff1d87839a52e39ffa66f96313f91b08734d4accd9cecc71d78fc2eaa71963a"],["t","tgfnostrpod"],["p","fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52"],["p","748bfa87c437b294164d1784b324a0d2e9495c8268e0044e3c7796a3b158c9d8"],["p","fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52"],["p","45c41f21e1cf715fa6d9ca20b8e002a574db7bb49e96ee89834c66dac5446b7a"],["p","59cacbd83ad5c54ad91dacf51a49c06e0bef730ac0e7c235a6f6fa29b9230f02"],["t","nostrovia"],["p","bbc73cae41502ddad7a4112586dcaf4422810d60aa4b57c637ccd1a746b07844"],["p","fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52"],["p","b9a537523bba2fcdae857d90d8a760de4f2139c9f90d986f747ce7d0ec0d173d"],["p","fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52"],["r","https://w3w.co"],["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"],["p","599c4f2380b0c1a9a18b7257e107cf9e6d8b4f8dea06c18c84538d311ff2b28c"],["p","6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93"],["r","https://nostr.report"]]}]"###
        ])
    }) {
        if let p = PreviewFetcher.fetchNRPost("a3d05222ad9459511b66814348eff9688f24edc06d1f86897636ae7c7bb2e031") {
            PostOrThread(nrPost: p)
        }
    }
}


#Preview("PostOrThread, too high") {
    PreviewContainer({ pe in
        pe.parseMessages([
            ###"["EVENT", "pp", {"pubkey":"6e75f7972397ca3295e0f4ca0fbc6eb9cc79be85bafdd56bd378220ca8eee74e","content":"Good morning #coffeechain ☕ 💜 https://nostrcheck.me/media/public/nostrcheck.me_6645701053325405701698657867.webp ","id":"f2e2b40834c8600bb93e72230d278c965ab5a95690efe02a8d028a9457891216","created_at":1698657877,"sig":"4e072eb0240e3ad03c468cee97082a8d346f34fa8eafe76f1070a622ab09e65fea96156dcba14659bdd0183e489057d7721e7fd6bb6663b9c40de8adec6fff61","kind":1,"tags":[["t","coffeechain"]]}]"###,
            ###"["EVENT", "pp", {"pubkey":"c89cf36deea286da912d4145f7140c73495d77e2cfedfb652158daa7c771f2f8","content":"gm from 🇯🇵 to 🇩🇪 nostr:npub1de6l09erjl9r990q7n9ql0rwh8x8n059ht7a267n0q3qe28wua8q20q0sd 🫂🍶✨","id":"ea4ea2b6ec2e2208aa2be575769114378c7d73b31a35abf345a8d6a60c949182","created_at":1698658838,"sig":"8c34b3be922abc5ea573f1a7035dfc6e6b42a067afa21070e5a0046fe13ef59548f9361293c40a3aba942a7f4e90bdb80e29244ba0fe9e8e812bc652ee0a0c64","kind":1,"tags":[["e","f2e2b40834c8600bb93e72230d278c965ab5a95690efe02a8d028a9457891216"],["p","6e75f7972397ca3295e0f4ca0fbc6eb9cc79be85bafdd56bd378220ca8eee74e"],["p","6e75f7972397ca3295e0f4ca0fbc6eb9cc79be85bafdd56bd378220ca8eee74e"]]}]"###
        ])
    }) {
        if let p = PreviewFetcher.fetchNRPost("ea4ea2b6ec2e2208aa2be575769114378c7d73b31a35abf345a8d6a60c949182", withReplyTo: true, withParents: true) {
            SmoothListMock {
                PostOrThread(nrPost: p)
            }
        }
    }
}


#Preview("NRTextFixed") {
    VStack {
        NRTextFixed("Some text with a tag [#bitcoin](nostur:t:bitcoin)", height: 128, themes: Themes.default)
            .background(Color.red)
        
        NRTextFixed("Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long Some text long", height: 128, themes: Themes.default)
            .background(Color.blue)
        
        Text("What")
            .background(Color.green)
    }
    .environmentObject(Themes.default)
    .environmentObject(DIMENSIONS())
}

struct NRTextFixed: UIViewRepresentable {
    typealias UIViewType = UITextView
    
    private let attributedString: NSAttributedString
    private let plain: Bool
    private let themes: Themes
    private let height: CGFloat
    private let fontColor: Color
    private let accentColor: Color?
    
    // Height calculation is expensive, so calculate before in background, then pass as prop.
    // see AttributedStringWithPs.
    // For other situations maybe use GeometryReader
    init(_ attributedString: NSAttributedString, plain: Bool = false, height: CGFloat, themes: Themes = Themes.default, fontColor: Color? = nil, accentColor: Color? = nil) {
        self.attributedString = attributedString
        self.plain = plain
        self.themes = themes
        self.height = height
        self.fontColor = fontColor ?? themes.theme.primary
        self.accentColor = accentColor ?? themes.theme.accent
    }
    
    init(_ text: String, plain: Bool = false, height: CGFloat, themes: Themes = Themes.default, fontColor: Color? = nil, accentColor: Color? = nil) {
        self.themes = themes
        self.height = height
        self.fontColor = fontColor ?? themes.theme.primary
        self.accentColor = accentColor ?? themes.theme.accent
        do {
//            let finalText = try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            
            let mutableAttributedString = try NSMutableAttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            let attributes:[NSAttributedString.Key: NSObject] = [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor(self.fontColor)
            ]
            
            mutableAttributedString.addAttributes(
                attributes,
                range: NSRange(location: 0, length: mutableAttributedString.length)
            )
            
            mutableAttributedString.addHashtagIcons()
            
            self.attributedString = NSAttributedString(attributedString: mutableAttributedString)
        }
        catch {
//            let finalText = AttributedString(text)
            
            let mutableAttributedString = NSMutableAttributedString(string: text)
            let attributes:[NSAttributedString.Key: NSObject] = [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor(self.fontColor)
            ]
            
            mutableAttributedString.addAttributes(
                attributes,
                range: NSRange(location: 0, length: mutableAttributedString.length)
            )
            
            mutableAttributedString.addHashtagIcons()
            
            L.og.error("NRTextParser: \(error)")
            self.attributedString = NSAttributedString(attributedString: mutableAttributedString)
        }
        self.plain = plain
    }
    
    func makeUIView(context: Context) -> UITextView {
//        105.00 ms    0.9%    0 s           protocol witness for UIViewRepresentable.makeUIView(context:) in conformance NRTextFixed
//        105.00 ms    0.9%    50.00 ms            NRTextFixed.makeUIView(context:)

        let view = UITextView()
//        _ = view.layoutManager
        view.isScrollEnabled = false
        view.textColor = UIColor(self.fontColor)
        view.tintColor = UIColor(accentColor ?? themes.theme.accent)
        view.isSelectable = true
        view.isEditable = false
        view.dataDetectorTypes = plain ? [] : [.link]
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.attributedText = self.attributedString
        
        view.translatesAutoresizingMaskIntoConstraints = false
        //        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
    }
    
    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let dimensions = proposal.replacingUnspecifiedDimensions(
            by: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        
        return CGSize(width: dimensions.width, height: height)
    }
    
    func sizeThatFits(_ proposal: CGSize, uiView: UITextView) -> CGSize {
        let size = CGSize(width: proposal.width, height: CGFloat.greatestFiniteMagnitude)
        let fittingSize = uiView.sizeThatFits(size)

        // You can use fittingSize.height if you want the height to be dynamic based on content.
        // If you have a specific height in mind, replace fittingSize.height with that value.
        return CGSize(width: proposal.width, height: fittingSize.height)
    }
}

extension NSMutableAttributedString {
    
    func addHashtagIcons() {
        let matches = NRTextParser.htRegex.matches(in: string, options: [], range: NSRange(location: 0, length: length))
        let reversedMatches = Array(matches.reversed())

        for match in reversedMatches {
            if match.numberOfRanges == 1 {
                let contentRange = match.range(at: 0)
                let tagString = (string as NSString).substring(with: contentRange)
                guard let tagImage = NRTextParser.shared.hashtagIcons[tagString.lowercased()] else { continue }
                
                let appendingImage = NSMutableAttributedString(string: " ")
                appendingImage.append(tagImage)
                
                self.insert(appendingImage, at: contentRange.upperBound)
            }
        }
    }
}
