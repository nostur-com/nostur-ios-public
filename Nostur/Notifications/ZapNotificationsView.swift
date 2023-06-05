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
        var links = [String]()
        for index in fails.failedZaps.indices {
            if let eventId = fails.failedZaps[index].eventId {
                links.append("[post #\(index+1)](nostur:e:\(eventId)): \(fails.failedZaps[index].error)")
            }
            else {
                links.append("[contact #\(index+1)](nostur:p:\(fails.failedZaps[index].contactPubkey)): \(fails.failedZaps[index].error)")
            }
        }
        return links.joined(separator: "\n")
    }
    
    var body: some View {
        VStack {
            switch notification.type {
            case .failedZaps:
                if let parsed = try? JSONDecoder().decode(FailedZaps.self, from: notification.content.data(using: .utf8)!) {
                    let forRendering = "Zaps failed on: \(createErrorLinks(parsed))."
                    if let rendered = try? AttributedString(markdown: forRendering, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(rendered)
                    }
                    else {
                        Text(notification.content)
                    }
                }
            case .failedZapsTimeout:
                if let parsed = try? JSONDecoder().decode(FailedZaps.self, from: notification.content.data(using: .utf8)!) {
                    let forRendering = "Zaps failed on: \(createLinks(parsed)) (Timeout)."
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
        VStack {
            if let pNotification = PreviewFetcher.fetchPersistentNotification() {
                ZapNotificationView(notification: pNotification)
                    .padding(10)
                    .background(Color.systemBackground)
                    .boxShadow()
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
            }
        }
            .withPreviewEnvironment({ pe in
                pe.loadContacts()
                pe.loadZapsNotifications()
            })
    }
}
