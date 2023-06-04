//
//  ZapNotificationsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/06/2023.
//

import SwiftUI

struct ZapNotificationView: View {
    var notification:PersistentNotification
    
    var body: some View {
        VStack {
            if let rendered = try? AttributedString(markdown: notification.content, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(rendered)
            }
            else {
                Text(notification.content)
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
