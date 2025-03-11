//
//  PostDetailPreviews.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2025.
//

import SwiftUI
import NavigationBackport

#Preview("Kind1063detail") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadKind1063()
    }) {
        NBNavigationStack {
            if let kind1063 = PreviewFetcher.fetchNRPost("ac0c2960db29828ee4a818337ea56df990d9ddd9278341b96c9fb530b4c4dce8") {
                PostDetailView(nrPost:kind1063)
            }
        }
    }
}

#Preview("Kind1063detailQuoted") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadKind1063()
    }) {
        NBNavigationStack {
            if let kind1063q = PreviewFetcher.fetchNRPost("71a965d8e8546f8927cea23ad865a429dbec0215f36c5e0edad2323eb00f4851") {
                PostDetailView(nrPost:kind1063q)
            }
        }
    }
}

#Preview("ReplyAndParentView") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.parseMessages([
            ###"["EVENT","485cefc1-2f85-402e-a136-691557f322c8",{"content":"https://youtube.com/shorts/cZenQR8tgV8?feature=share\n\nIf even _she_ is speaking out about Canada's new bill C-11, it's bad. She's a 100% mainstream comedian who got her start during lockdown.","created_at":1680327426,"id":"5988f18416a6d2702a61df9dedc318f18d0d5778a020464222138edab386eee7","kind":1,"pubkey":"ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc","sig":"efad8bf0580ee6a36f6ebd48ab3fba940d9fdc5d5fcf866b6d609ac52c1b24a7acb16277890ea770a8d4328018c1ec7b7ef84e7ffa19b8f9929a36300adc4b33","tags":[["r","https://youtube.com/shorts/cZenQR8tgV8?feature=share"]]}]"###,
            ###"["EVENT","16dbd7e2-af00-4c7d-9258-f5413d75b95f",{"content":"The fact thay she thinks an “amendment to protect digital creators” makes the bill ok is so childishly naive it hurts. ","created_at":1680333364,"id":"5e80b08b76e81e549c4554e161dfeb67a09da859e4706a989876a5ec42016d9a","kind":1,"pubkey":"b9e76546ba06456ed301d9e52bc49fa48e70a6bf2282be7a1ae72947612023dc","sig":"5c31c120473800d878a5391ad2055b20404a4d97d20c08116f0931737559aea7d8e26febf64f4e24385c637d1e8b84ede32ca498a75190b0aaaba3821ac1bd3a","tags":[["e","5988f18416a6d2702a61df9dedc318f18d0d5778a020464222138edab386eee7"],["p","ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc"]]}]"###,
            ###"["EVENT","a2533e43-5968-40dd-a986-131e839cbb84",{"content":"Her being publicly against it at all is a win. And the amendment was cancelled.","created_at":1680333872,"id":"a4508aa658b12d51a56613c51da096d7791eb207d3b11407089c633ff73f668d","kind":1,"pubkey":"ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc","sig":"a1a46a31a1d11175cfc8452210b436d731f3b8615254ec51063f4124a250cc544e40ab54899b243f7637c5778f093d869a6b9f54e1e30f9b9245c07d6df37b9f","tags":[["e","5988f18416a6d2702a61df9dedc318f18d0d5778a020464222138edab386eee7"],["e","5e80b08b76e81e549c4554e161dfeb67a09da859e4706a989876a5ec42016d9a"],["p","ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc"],["p","b9e76546ba06456ed301d9e52bc49fa48e70a6bf2282be7a1ae72947612023dc"]]}]"###])
    }) {
        NBNavigationStack {
            if let xx = PreviewFetcher.fetchNRPost("a4508aa658b12d51a56613c51da096d7791eb207d3b11407089c633ff73f668d") {
                PostDetailView(nrPost: xx)
            }
        }
    }
}

#Preview("YouTubePreviewInDetail") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        NBNavigationStack {
            if let yt2 = PreviewFetcher.fetchNRPost("0000014de66e08882bd36b6b7b551a774f85fe752a18070dc8658d7776db7e69") {
                PostDetailView(nrPost: yt2)
            }
            
        }
    }
}

#Preview("YouTubeInDetail") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.parseMessages([
            ###"["EVENT","e24e08cc-9e36-4a54-8a33-1d1fc84ae95c",{"content":"https://youtu.be/QU9kRF9tHPU","created_at":1681073179,"id":"c7b4ef377ee4f6d71f6f59bc6bad607acb9c7c3675e3c0b2ca0ad2442b133e49","kind":1,"pubkey":"82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2","sig":"2bec825a1db31653187d221b69965e992a28d5a0913aa286c89fa23606fc41f4ad7b146a4844a136ba2865566c958b509e544c6620e25f329f239a7be0d6f87b","tags":[]}]"###]
        )
    }) {
        NBNavigationStack {
            if let yt = PreviewFetcher.fetchNRPost("c7b4ef377ee4f6d71f6f59bc6bad607acb9c7c3675e3c0b2ca0ad2442b133e49") {
                ScrollView {
                    PostDetailView(nrPost: yt)
                }
            }
            
        }
    }
}

#Preview("ReplyAndParent4") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
    }) {
        NBNavigationStack {
            if let v = PreviewFetcher.fetchNRPost("bb15e6165180d31c36b6c3e0baf082eeb949aa473c59e37eaa8e2bb29dc46422") {
                PostDetailView(nrPost: v)
            }
            
        }
    }
}

#Preview("ReplyAndParent5") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
    }) {
        NBNavigationStack {
            if let lastReply = PreviewFetcher.fetchNRPost("2026c6b0f0d887aa76cc60f0b3050fe940c8eca9eb479391acb493bb40e4d964") {
                PostDetailView(nrPost: lastReply)
            }
            
        }
    }
}

#Preview("ReplyAndParentView6_Previews") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
    }) {
        NBNavigationStack {
            if let rootWithReplies = PreviewFetcher.fetchNRPost("6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81") {
                PostDetailView(nrPost: rootWithReplies)
            }
        }
    }
}

#Preview("ReplyAndParentView7_Previews") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
    }) {
        NBNavigationStack {
            if let v = PreviewFetcher.fetchNRPost("c0d76c3c968775a62ca1dea28a73e1fc86d121e8e5e17f2e35aaad1436075f51") {
                PostDetailView(nrPost: v)
            }
        }
    }
}

#Preview("BetterReplies_Previews") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
    }) {
        NBNavigationStack {
            if let matt = PreviewFetcher.fetchNRPost("e593fc759291a691cd0127643a0b9fac9d92613952845e207eb24332937c59d9") {
                PostDetailView(nrPost: matt)
            }
        }
    }
}

// Content to debug cutoff text, wrong .fixedSize etc
#Preview("Quotes in quotes (Detail)") {
    PreviewContainer({ pe in
    
        pe.parseMessages([
            ###"["EVENT","qInq",{"id":"ff42811e971737587e4438356891b3f88cf8c06a609cec23a3bd6e3b3ac52616","sig":"e4798a9b9d7d4a92954f997928dbfcaf3e728a3e7ce6a829f835ad92ba06135631ff2806e8d488e98a1f424bb65930d0f285c25da959e218e15c251e0b18d7a9","tags":[],"created_at":1721000374,"pubkey":"27c4d775bedfaf861452eb366e5db3d9957eb2d4a226cd8856dd5e83760abcae","kind":1,"content":"YES\n\nnostr:note16mh6fvxk9deqlyd75l52ucfvh8ucqy2d95pgzxkw7rjwa67jcj0q6a6yvg"}]"###,
            ###"["EVENT","qInq",{"sig":"e5b5096155e52629ba734fc1fd6df1991e428a6974525c3915d27ca2c19dfe30c8281985f17c9ddd546b83387317fc00c1582763dde49c11aebb0049b7797477","created_at":1721000275,"content":"Did someone say circle jerk ?\nnostr:nevent1qqsdkdmkklqxcsnkhhntcgt5t7e5cxc63h4ftt8wj988jmz0p3ue65cpzpmhxue69uhkutn0dvczummjvuhsygqcjpws5htz82up4x96nrzc902l2le9qmrtszystlzen4dqkg5mpqpsgqqqqqqsugny48","kind":1,"pubkey":"45b35521c312a5da4c2558703ad4be3d2e6d08c812551514c7a1eb7ab5fa0f04","tags":[["e","db3776b7c06c4276bde6bc21745fb34c1b1a8dea95acee914e796c4f0c799d53","","mention"],["p","18905d0a5d623ab81a98ba98c582bd5f57f2506c6b808905fc599d5a0b229b08","","mention"],["q","db3776b7c06c4276bde6bc21745fb34c1b1a8dea95acee914e796c4f0c799d53"],["zap","18905d0a5d623ab81a98ba98c582bd5f57f2506c6b808905fc599d5a0b229b08","wss://filter.nostr.wine/npub1rzg96zjavgatsx5ch2vvtq4atatly5rvdwqgjp0utxw45zeznvyqfdkxve?broadcast=true","0.9"],["zap","45b35521c312a5da4c2558703ad4be3d2e6d08c812551514c7a1eb7ab5fa0f04","wss://n.ok0.org/","0.1"]],"id":"d6efa4b0d62b720f91bea7e8ae612cb9f980114d2d02811acef0e4eeebd2c49e"}]"###,
            ###"["EVENT","qInq",{"pubkey":"18905d0a5d623ab81a98ba98c582bd5f57f2506c6b808905fc599d5a0b229b08","created_at":1720999998,"tags":[["q","8db97c069042d7201e25b7b52a771442c9418ac682f95aab2de794f090695009"],["p","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"]],"content":"I am now 😂😂\nnostr:note13kuhcp5sgttjq839k76j5ac5gty5rzkxstu442edu720pyrf2qys5pm3x7","kind":1,"id":"db3776b7c06c4276bde6bc21745fb34c1b1a8dea95acee914e796c4f0c799d53","sig":"51a946d66c1ca6be0d14ab441e3c803ab15eaa3095aa161f2cd9f5c30fe32c4005f523d13a08f3fe0d9c314e17edeb4c9bcd01d77bbea8a35d929bae6c97f61b"}]"###,
            ###"["EVENT","qInq",{"tags":[["q","4d5059e97b3e338afc8999e86fdf8b406377d36739a29e0009b912c946dcb0d7"],["p","18905d0a5d623ab81a98ba98c582bd5f57f2506c6b808905fc599d5a0b229b08"]],"pubkey":"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","sig":"277e4c7674266d0b138436bb78d07e92e834f4345728e57a17c153740e7961a51b838ad7396571af3aa71f60ddba88d9ee648dca36f3a87dcbf544446a6bac9d","id":"8db97c069042d7201e25b7b52a771442c9418ac682f95aab2de794f090695009","kind":1,"content":"Are you on Nostur too? \nnostr:note1f4g9n6tm8cec4lyfn85xlhutgp3h05m88x3fuqqfhyfvj3kukrtsvffwnh","created_at":1720999883}]"###,
            ###"["EVENT","qInq",{"pubkey":"18905d0a5d623ab81a98ba98c582bd5f57f2506c6b808905fc599d5a0b229b08","id":"4d5059e97b3e338afc8999e86fdf8b406377d36739a29e0009b912c946dcb0d7","created_at":1720999817,"tags":[["p","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"],["p","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"]],"content":"Interesting 🤔 nostr:note1sgln5lzjs9zkj7xxphx7yvg46egxm27cw2fu4v95ancgzr204ccszcm53g","sig":"64f4d6e3d4572fc4c14834fccfbf075955d8a4adfdce701eeb4e6702016a20bf12213f0e8d44f53da52691588dc90da996eed6d4e7d0a8c890f52902f6bf2022","kind":1}]"###,
            ###"["EVENT","qInq",{"created_at":1720999255,"kind":1,"id":"823f3a7c5281456978c60dcde23115d6506dabd87293cab0b4ecf0810d4fae31","sig":"2a4b65bbc3811f421238249181ed706d0f1a8f1c9683f4a123f96e9fa6f1b18584ce971ad84863898e28b2bbba696fc2c8fc392ee0d5f7a9b1d8bf58dd3135df","content":"This is getting out control 🤣\nnostr:note13awfa3utvx6zrm3tclj6yu7d9dk7ncuzvnkjcufw9kmcwtjhukysknguaq","pubkey":"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","tags":[["q","8f5c9ec78b61b421ee2bc7e5a273cd2b6de9e38264ed2c712e2db7872e57e589"],["p","cb5a5f84f511e5c8039210f3887272ea8d806e5f7f5b26cb443f3b6ec8b15664"]]}]"###,
            ###"["EVENT","qInq",{"kind":1,"created_at":1720999175,"content":"👇👀 🫂\nnostr:nevent1qqsvgqmmtpe05vdj7ea9xcdx0qwxw70jhvzyavuddgm5e9gf2j5tt2qpz4mhxue69uhkummnw3ezummcw3ezuer9wchsyg8cumryxsh3upfysp3suflpq9kuud0u8fs5uczrflh54gjsxv5v4ypsgqqqqqqstl4h3r","id":"8f5c9ec78b61b421ee2bc7e5a273cd2b6de9e38264ed2c712e2db7872e57e589","pubkey":"cb5a5f84f511e5c8039210f3887272ea8d806e5f7f5b26cb443f3b6ec8b15664","sig":"87153d19869a4b6306455a0228fc5d27ee5d95bb2b10ae756a2154c8c7f43c845d9a9cfe534c5efdbaee24e03e9486f2e380827e8630131a5d8aca32fa68ea60","tags":[["e","c4037b5872fa31b2f67a5361a6781c6779f2bb044eb38d6a374c950954a8b5a8","","mention"],["p","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","","mention"],["q","c4037b5872fa31b2f67a5361a6781c6779f2bb044eb38d6a374c950954a8b5a8"],["zap","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","wss://relay.wellorder.net","0.9"],["zap","cb5a5f84f511e5c8039210f3887272ea8d806e5f7f5b26cb443f3b6ec8b15664","wss://nostrelay.yeghro.site/","0.1"]]}]"###,
            ###"["EVENT","qInq",{"tags":[["q","29df2a0d9a508770244ef39c8a7ead6b85abe6155f2f91a2b0b203765d882d56"],["p","9d7d214c58fdc67b0884669abfd700cfd7c173b29a0c58ee29fb9506b8b64efa"]],"sig":"b3319711937594a7faffe08ea6b6780f8d4fbcef24bdb19d2194e6b42fe186f969fb46740ef705d8996267f95114710d1c8c3ebf74432986cd180f33acb67d1d","created_at":1720999034,"pubkey":"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","content":"Shhh…don’t ask. Just quote. \nnostr:note1980j5rv62zrhqfzw7wwg5l4ddwz6hes4tuherg4skgphvhvg94tqxf4eyj","kind":1,"id":"c4037b5872fa31b2f67a5361a6781c6779f2bb044eb38d6a374c950954a8b5a8"}]"###,
            ###"["EVENT","qInq",{"kind":1,"created_at":1720998992,"tags":[["p","dc4cd086cd7ce5b1832adf4fdd1211289880d2c7e295bcb0e684c01acee77c06"],["p","dc4cd086cd7ce5b1832adf4fdd1211289880d2c7e295bcb0e684c01acee77c06"]],"id":"29df2a0d9a508770244ef39c8a7ead6b85abe6155f2f91a2b0b203765d882d56","content":"I’m sure it will all make sense at some point 🤔 nostr:note1ey2xw4y274cm9urx8ll80xkxt7c6uyu798g2g67ssn9t2skd35xq4tc7cv","sig":"31d1ea3f349fcb41063475a8a5229c36058278240b3f998d5736cad0278b4c0af80d37fc31b1ac1c2ce9bc23b2f09941b8cc89ab898c0d1a4a7eb57ee97a465f","pubkey":"9d7d214c58fdc67b0884669abfd700cfd7c173b29a0c58ee29fb9506b8b64efa"}]"###,
            ###"["EVENT","qInq",{"kind":1,"id":"c91467548af571b2f0663ffe779ac65fb1ae139e29d0a46bd084cab542cd8d0c","pubkey":"dc4cd086cd7ce5b1832adf4fdd1211289880d2c7e295bcb0e684c01acee77c06","sig":"013c3cfafa7d7e5fe96b87860583828f8d54db96bce15dc472b2c2d14673eae836abbba2b4cdc05db18351dc4ac902dbe91a30e6f2f909ca10a05677a6e409fa","tags":[["e","31136e20653f4f4915564b0b1451ec667dd7c139a6d2b848e86fab5066c26705","","mention"],["p","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","","mention"],["q","31136e20653f4f4915564b0b1451ec667dd7c139a6d2b848e86fab5066c26705"],["zap","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","ws://localhost:4869","1.0"]],"created_at":1720998809,"content":"I don't get it\nnostr:nevent1qqsrzymwypjn7n6fz4tykzc528kxvlwhcyu6d54cfr5xl26svmpxwpgpr4mhxue69uhkummnw3ezucnfw33k76twv4ezuum0vd5kzmp0qgsr7acdvhf6we9fch94qwhpy0nza36e3tgrtkpku25ppuu80f69kfqrqsqqqqqpu40cm2"}]"###,
            ###"["EVENT","qInq",{"pubkey":"3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","sig":"7a79116e06e26e958e9c934aba9dd4df43fe497b0b2059b7640aa9b7eaa9b2c2fee0b558ea931752b9967a8cd8029ef4e44e60887ae9c1a16cef9749aadc9e4f","kind":1,"created_at":1720998527,"tags":[["e","4ce3a2cec3d46b6164e7eecb740be5ab017cc2a54f3771c6de72de650eb6ff7f","","mention"],["p","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","","mention"],["q","4ce3a2cec3d46b6164e7eecb740be5ab017cc2a54f3771c6de72de650eb6ff7f"]],"content":"👀\nnostr:nevent1qqsyecazempag6mpvnn7ajm5p0j6kqtuc2j57dm3cm089hn9p6m07lcpzdmhxue69uhk7enxvd5xz6tw9ec82c30qgs03ekxgdp0rczjfqrrpcn7zqtdec6lcwnpfesyxnl0f239qvege2grqsqqqqqpz4f9hv","id":"31136e20653f4f4915564b0b1451ec667dd7c139a6d2b848e86fab5066c26705"}]"###,
            ###"["EVENT","qInq",{"kind":1,"sig":"23bb6ae7bae13c161e0f30b6f20fc1accfeba2a9b41390f0fcb14acb0162a8fd19be4e52d382d766efa8efb58773eeb8620202e91d50dddd471e16689266e80b","created_at":1720998269,"id":"4ce3a2cec3d46b6164e7eecb740be5ab017cc2a54f3771c6de72de650eb6ff7f","tags":[],"content":"“Quote tweeting” is the social media equivalent of a circle jerk. ","pubkey":"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"}]"###
           
        ])
        
        SettingsStore.shared.fullWidthImages = false
    }) {
        NBNavigationStack {
            Color.red
                .frame(height: 30)
                .debugDimensions("spacer", alignment: .center)
            
            if let qq = PreviewFetcher.fetchNRPost("ff42811e971737587e4438356891b3f88cf8c06a609cec23a3bd6e3b3ac52616") {
                PostDetailView(nrPost: qq)
            }
        }
    }
}
