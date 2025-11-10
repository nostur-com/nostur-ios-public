//
//  NoteRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/03/2023.
//

import SwiftUI
import NukeUI
import Nuke
import NukeVideo

@available(iOS 18.0, *)
#Preview("NoteRow previews") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadReposts()
        pe.loadHighlights()
        pe.loadKind1063()
        pe.parseMessages([
            ###"["EVENT","R",{"kind":1,"created_at":1739053162,"pubkey":"3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d","tags":[["-"],["client","Nostur"]],"id":"c899f14bdfd2aa6943ae6d9d55a55839f65f9bb0994d3e9c4022603df620ac7a","sig":"0dfe5d49a9555c22e6d3849eae9262fba20ddcc74335f3203faf85c1d660e8be2c95585145e66e729b2133f0f2cf1d719f160df33b039522aaa4c304ae4dd05b","content":"Turns out https://lockbox.fiatjaf.com/ is the best place to publish your stuff that you only want people who really understand Nostr to read (i.e. people who are using outbox-capable clients, or relay-browsers)."}]"###
        ])
    }) {
        PreviewFeed { // CHANGE 1 == 2 to 1 == 1 to preview
            let testMe: Set<Int> = [20]
            Group {
                if testMe.contains(1), let p = PreviewFetcher.fetchNRPost("1920b9351f01dd92dad21a9eef04781b896cb45260dfc02d9e9c05bda6dfef77") {
                        // A POST WITH CODE IN QUOTE
                        Box {
                            PostRowDeletable(nrPost: p, fullWidth: true, theme: Themes.default.theme)
                        }

                        Box {
                            PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                        }
                    }
                if testMe.contains(2), let p = PreviewFetcher.fetchNRPost("347c5332d508c99d57b25dcaad7ee91f4922088b3d9395c447055953d02084e7") {
                        // A POST WITH CODE
                        Box {
                            PostRowDeletable(nrPost: p, fullWidth: true, theme: Themes.default.theme)
                        }

                        Box {
                            PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                        }
                    }
                if testMe.contains(3), let p = PreviewFetcher.fetchNRPost("115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc") {
                    // A POST WITH A @MENTION
//                        Box {
//                            PostRowDeletable(nrPost: p, fullWidth: true, theme: Themes.default.theme)
//                        }

                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }


                if testMe.contains(4), let p = PreviewFetcher.fetchNRPost("576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113") {
                    // A POST WITH A YOUTUBE LINK (WITH PREVIEW)
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(4), let p = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0") {
                    // A POST WITH A @MENTION
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }
            }
            Group {
                if testMe.contains(5), let p = PreviewFetcher.fetchNRPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3") {
                    // A POST WITH WITH JUST TEXt
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(6), let p = PreviewFetcher.fetchNRPost("d3b581761bab06fbe727b12b22c33c7b8768d7d9681b45cb6b1f4ad798496e14") {
                    // A POST WITH LINK PREVIEW WITH IMAGE
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(7), let p = PreviewFetcher.fetchNRPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe") {
                    // A QUOTE REPOST, USING OLD METHOD (#[5])
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(8), let p = PreviewFetcher.fetchNRPost("bf0ca9422b83a35fd3384d4149314bfff9f05e025b5138c9db85d90a41b03ad9") {
                    // A POST WITH 1 GIF
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(9), let p = PreviewFetcher.fetchNRPost("6687ee15b74160673449e2bf667d88e246d8101418e167679f2aa10df3bb7c06") {
                    // A POST WITH 1 IMAGE
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(10), let p = PreviewFetcher.fetchNRPost("82fcaaa11259aa5f505f1e3a6de06c2b7265179d3d05ef0b74824c4b7ff7eab8") {
                    // A POST WITH 1 IMAGE AND 14 MORE ITEMS
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(11), let p = PreviewFetcher.fetchNRPost("5099246907e78edde0169c419543c01dd312fbe2645106c58f476efd65c2f66b") {
                    // A POST WITH A #BITCOIN HASHTAG AND A SINGLE IMAGE
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }


                if testMe.contains(12), let p = PreviewFetcher.fetchNRPost("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3") {
                    // POST WITH MARKDOWN, EMBEDDED POST/W IMAGE AND 13 MORE ITEMS
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }


                if testMe.contains(13), let p = PreviewFetcher.fetchNRPost("102177a51af895883e9256b70b2caff6b9ef90230359ee20f6dc7851ec9e5d5a") {
                    // POST WITH A LINKPREVIEW WITHOUT IMAGE META TAG. AND 1 MORE ITEM
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(14), let p = PreviewFetcher.fetchNRPost("6701067d37887024cd221c45e77cf3f0e1ef76589006739617ccc8962719a024") {
                    // POST WITH A LINKPREVIEW WITHOUT IMAGE META TAG
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }
            }
            Group {
                if testMe.contains(15), let p = PreviewFetcher.fetchNRPost("da9454d3143de0139cd9e554ed29aa19606657c28dfbc0c12ac12e14db645ab3") {
                    // POST WITH A LINKPREVIEW WITH A VERY WIDE IMAGE
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(16), let p = PreviewFetcher.fetchNRPost("59eeb003cf61b329a0c3be1c2d36aae7b6342ec7092d0ee71a4b7d104de8ea10") {
                    // POST WITH A VIDEO
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }


                if testMe.contains(17),
                    let p = PreviewFetcher.fetchNRPost("cae89d3f54cacf1dfd4ca97077a033350538d1bbdc19dfb571f0b76afe2c9fbc"),
                    let q = PreviewFetcher.fetchNRPost("e61ac6b699158d279adf59533ded2df2cbe6e711204c0d1d31154b59b8a41e7f") {
                    let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
                    // POST WITH A VIDEO
                    VStack {
                        Box {
                            PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                        }
                        
                        Box {
                            PostRowDeletable(nrPost: q, theme: Themes.default.theme)
                        }
                    }
                }


                if testMe.contains(18), let p = PreviewFetcher.fetchNRPost("71a965d8e8546f8927cea23ad865a429dbec0215f36c5e0edad2323eb00f4851") {
                    // A POST EMBEDDING A NIP-94 IMAGE (FILE META DATA) (KIND 1063) WITH nostr:nevent1...
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(19), let p = PreviewFetcher.fetchNRPost("ac0c2960db29828ee4a818337ea56df990d9ddd9278341b96c9fb530b4c4dce8") {
                    // A NIP-94 IMAGE (FILE META DATA) (KIND 1063)
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }


                if testMe.contains(20) {
//                    if let p = PreviewFetcher.fetchNRPost("68b3330358ab3e554183724bed09cc704e62e9b3e790efbb7e819c81905e71a3") {
//                        // A HIGHLIGHT (KIND 9802)
//                        Box {
//                            PostRowDeletable(nrPost: p, theme: Themes.default.theme)
//                        }
//                    }
                    
                    if let p = PreviewFetcher.fetchNRPost("16c11b81c745a0e6f9a0b0c4d86265e3c3b989525826f55e2d96bbe3c8b89170") {
                        // A QUOTE HIGHLIGHT (KIND 9802), quote in comment tag
                        Box {
                            PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                        }
                    }
                }

                if testMe.contains(21), let p = PreviewFetcher.fetchNRPost("2b6996d0695569d97f7dd6fd8f2a32428d4df5ca3f28bfcad6a6cc087ff79e25") {
                    // A POST WITH A NOSTR:NRPFOFILE1 LINK (DOESN'T WORK?) TODO: CHECK THIS
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(22), let p = PreviewFetcher.fetchNRPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e") {
                    // A POST WITH JUST 1 LINE OF TEXT
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(23), let p = PreviewFetcher.fetchNRPost("7d96834f60c5411be97fe9e4b07e3221c56df531543a11a1d67ff81168033e8e") {
                    // REPOST JUST TEXT
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }

                if testMe.contains(24), let p = PreviewFetcher.fetchNRPost("fdf989cbe5d26d874a4afaf8a78861fcd3267619e7db467a549a6b33c6dbeeab") {
                    // REPOST POST WITH IMAGE
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }
                
                if testMe.contains(25), let p = PreviewFetcher.fetchNRPost("c899f14bdfd2aa6943ae6d9d55a55839f65f9bb0994d3e9c4022603df620ac7a") {
                    // RESTRICTED POST
                    Box {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                }
            }
        }
        .withSheets()
    }
}

@available(iOS 18.0, *)
#Preview("Debugging") {
    PreviewContainer({ pe in
        pe.parseMessages([
            ###"["EVENT", "bug", {"kind":1,"sig":"11858cacfa18147eb04c2e283775140cf1fc204f17b963ed40f75e6e54831467d5dcb646766c42873a3d5b2741339be0471fc87598057e68484620f2b78f7d3c","id":"0e090529d5fa674eeb07a3a17a012349ee6c1db56fa172fd3dc0f704f46a8e3e","tags":[],"pubkey":"f0019b0732a2b1a70360fb8f5ddb7f40544f8b46b0c928e300b519f6d53ec7c9","created_at":1737317165,"content":"ムカつくから死ねないけど、座りすぎは健康に悪いって話だよ。そこにJoin Nostrリンクがあるよ！滝は82メートルもあって、TikTokを運営する新たな合弁事業を設け、アメリカが合弁事業の50％の株式を持つことを明らかにしてれば勝手に育つと思ったら、本当にのど飴を取り出したんだろうが。"}]"###,
            ###"["EVENT", "bug", {"id":"2257f6241b888e264346187653ce186427b72a3b6b69838060567ea8b3c87f5e","kind":1,"created_at":1715162040,"sig":"b0abce338b466d6f253a4d35020b21a8a3a05d763d3c95c50c3dc6c5082be460ab14d042bbc279b28aa1ff460b30b2a24490d26a0fe221d88be35a5e9b75e2eb","content":"Search across long posts, live chats, torrents, communities and other stuff on Nostr.Band!\n\nThe default search query now runs across multiple event kinds on https://nostr.band. You can specify your preferred kind by adding \"kind:N\" to your query, or use our advanced search to select some of supported kinds.\n\nThe site also works a bit faster now, some bugs were fixed. \n\nNostr.Band app didn't get enough of our development attention recently, if you think there are other important missing or broken parts of it - let me know.","tags":[],"pubkey":"3356de61b39647931ce8b2140b2bab837e0810c0ef515bbe92de0248040b8bdd"}]"###,
            ###"["EVENT", "bug", {"content":"Nostur will publish to relays, but our data is on our device first, iCloud second, and third-party relays third. And you can still use a personal private relay for yourself if you want.\n\nWith this in mind, Nostur tries to let relays just be relays, not personal storage. Using relays for storage might end up centralising nostr, in the same way email, which used to be decentralised, is now mostly hosted by google and microsoft.\n\nIf you disagree with this mission or direction, Nostur’s source is released under GPL-3.0 license, so feel free to fork and create a different version.\n\nUltimately, the goal of Nostur is not to get more people to use Nostur, but to get more people to use nostr.","created_at":1742722193,"kind":9802,"pubkey":"9e8e8f0390bfd44e262f57914ae7d4ea834143e88e93b6f0bc687986423dfd96","sig":"73ea26f4a96c5cdec6047c73bea466d97219c66df362d93f8980785ab0b1940026aebbe6cdc82aa6c559d43d93a395279f515ed39b33e1717116bbbeaf99472a","id":"65464a220413c1441f363799e58fa4d9900e4c651a67a3eb7c9318c7befa13e8","tags":[["context","Nostur will publish to relays, but our data is on our device first, iCloud second, and third-party relays third. And you can still use a personal private relay for yourself if you want.\n\nWith this in mind, Nostur tries to let relays just be relays, not personal storage. Using relays for storage might end up centralising nostr, in the same way email, which used to be decentralised, is now mostly hosted by google and microsoft.\n\nIf you disagree with this mission or direction, Nostur’s source is released under GPL-3.0 license, so feel free to fork and create a different version.\n\nUltimately, the goal of Nostur is not to get more people to use Nostur, but to get more people to use nostr."],["alt","This is a highlight created in https://primal.net iOS application"],["a","30023:9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e:nostur-mission"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]]}]"###
        ])
    }) {
        if let p = PreviewFetcher.fetchNRPost("65464a220413c1441f363799e58fa4d9900e4c651a67a3eb7c9318c7befa13e8") {
            Box {
                PostRowDeletable(nrPost: p, theme: Themes.default.theme)
            }
        }
    }
    
}
