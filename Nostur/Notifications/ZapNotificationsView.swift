//
//  ZapNotificationsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/06/2023.
//

import SwiftUI

struct ZapNotificationView: View {
    var notification:PersistentNotification
    
    func createLinks(_ fails:FailedZaps) -> String {
        var links = [String]()
        for index in fails.failedZaps.indices {
            if let eventId = fails.failedZaps[index].eventId {
                links.append("[post #\(index+1)](nostur:e:\(eventId))")
            }
            else {
                links.append("[contact #\(index+1)](nostur:p:\(fails.failedZaps[index].contactPubkey))")
            }
        }
        return links.formatted(.list(type: .and))
    }
    
    func createErrorLinks(_ fails:FailedZaps) -> String {
        let postKey = String(localized: "post", comment: "The word \"post\" when used as post #1, post #2 and post #3.")
        let contactKey = String(localized: "contact", comment: "The word \"contact\" when used as contact #1, contact #2 and contact #3.")
        var links = [String]()
        for index in fails.failedZaps.indices {
            if let eventId = fails.failedZaps[index].eventId {
                links.append("[\(postKey) #\(index+1)](nostur:e:\(eventId)): \(fails.failedZaps[index].error)")
            }
            else {
                links.append("[\(contactKey) #\(index+1)](nostur:p:\(fails.failedZaps[index].contactPubkey)): \(fails.failedZaps[index].error)")
            }
        }
        return links.joined(separator: "\n")
    }
    
    var body: some View {
        VStack {
            switch notification.type {
            case .failedZaps:
                if let parsed = try? JSONDecoder().decode(FailedZaps.self, from: notification.content.data(using: .utf8)!) {
                    let forRendering = String(localized:"Zaps may have failed on: \(createErrorLinks(parsed)).", comment: "Message for possibly failed zaps on: (post 1, post 2, post 3...)")
                    if let rendered = try? AttributedString(markdown: forRendering, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(rendered)
                    }
                    else {
                        Text(notification.content)
                    }
                }
            case .failedZapsTimeout:
                if let parsed = try? JSONDecoder().decode(FailedZaps.self, from: notification.content.data(using: .utf8)!) {
                    let forRendering = String(localized: "Zaps failed on: \(createLinks(parsed)) (Timeout).", comment: "Message for failed zaps on: (contact #1, contact #2, contact #3...) because time out.")
                    if let rendered = try? AttributedString(markdown: forRendering, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(rendered)
                    }
                    else {
                        Text(notification.content)
                    }
                }
            default:
                if let rendered = try? AttributedString(markdown: notification.content, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(rendered)
                }
                else {
                    Text(notification.content)
                }
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
        .overlay(alignment: .topTrailing) {
            Ago(notification.createdAt).layoutPriority(2)
                .foregroundColor(.gray)
        }
    }
}

struct ZapNotificationView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadZapsNotifications()
        }) {
            VStack {
                if let pNotification = PreviewFetcher.fetchPersistentNotification() {
                    Box {
                        ZapNotificationView(notification: pNotification)
                    }
                }
            }
        }
    }
}
