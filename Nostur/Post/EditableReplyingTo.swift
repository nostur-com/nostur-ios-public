////
////  EditableReplyingTo.swift
////  Nostur
////
////  Created by Fabian Lachman on 13/07/2023.
////
//
//import SwiftUI
//
//struct EditableReplyingTo: View {
//    var body: some View {
//        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
//    }
//    
//    func replyingToUsernamesMarkDownString(_ event:Event) -> String? {
//        guard event.replyToId != nil || event.replyTo != nil else { return nil }
//        let tags = event.fastTags
//        guard tags.count < 50 else { return String(localized:"Replying to \(tags.count) people", comment: "Shown in a post, Replying to (X) people ") }
//
//        let pTags = Set(tags.filter { $0.0 == "p" }.map { $0.1 })
//        if (pTags.count > 6) {
//            let pTagsAsStrings = pTags.prefix(4).map { pubkey in
//                let username = contactUsername(fromPubkey: pubkey, event: event)
//                    .escapeMD()
//                return "[@\(username)](nostur:p:\(pubkey))"
//            }
//            return String(localized:"Replying to: \(pTagsAsStrings.joined(separator: ", ")) and \(pTags.count-4) others", comment: "Shown in a post, Replying: (names) and (x) others")
//        }
//        else if (!pTags.isEmpty) {
//            let pTagsAsStrings = pTags.map { pubkey in
//                let username = contactUsername(fromPubkey: pubkey, event: event)
//                    .escapeMD()
//                return "[@\(username)](nostur:p:\(pubkey))"
//            }
//            return String(localized:"Replying to: \(pTagsAsStrings.formatted(.list(type: .and)))", comment:"Shown in a post, Replying to (names)")
//        }
//        return nil
//    }
//}
//
//struct EditableReplyingTo_Previews: PreviewProvider {
//    static var previews: some View {
//        EditableReplyingTo()
//            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
//    }
//}
