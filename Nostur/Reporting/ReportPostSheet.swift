//
//  ReportPostSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/04/2023.
//

import SwiftUI

struct ReportPostSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    public let nrPost:NRPost
    @State private var reason = ReportType.spam
    @State private var comment:String = ""
    @State private var reportWhat = "Post" // to also report the profile, not just the post
    
    var body: some View {
        VStack {
            ScrollView {
                Box(nrPost: nrPost, navMode: .noNavigation) {
                    PostRowDeletable(nrPost: nrPost, hideFooter: true, missingReplyTo: true, theme: theme)
                }
                .disabled(true)
//                .overlay(
//                    Rectangle().opacity(0.02)
//                        .onTapGesture {
//
//                        }
//                )
            }
            .frame(maxHeight: 200)
            .padding(10)
//            .background(theme.listBackground)
            .clipped()
            
            Form {
                Section(header: Text("Report Information", comment: "Heading when entering Report details"), footer: VStack {
                    Text("Your report is public, other users can use your report to improve the network", comment: "Informational message")
                }) {
                    Picker(selection: $reason, label: Text("Reason", comment: "Label for the reason of a report")) {
                        Text("Impersonation", comment: "Menu item in choice list").tag(ReportType.impersonation)
                        Text("Spam", comment: "Menu item in choice list").tag(ReportType.spam)
                        Text("Nudity", comment: "Menu item in choice list").tag(ReportType.nudity)
                        Text("Profanity", comment: "Menu item in choice list").tag(ReportType.profanity)
                        Text("Illegal content", comment: "Menu item in choice list").tag(ReportType.illegal)
                    }
                    
                    Picker(selection: $reportWhat, label: Text("Report for", comment: "Label for choice of what to report")) {
                        Text("This post", comment: "Menu choice").tag("Post")
                        Text("This post & user", comment: "Menu choice").tag("Profile+Profile")
                    }
                        
                    TextField(String(localized:"Extra information", comment: "Label for report field to give extra information"), text: $comment)
                }
                .listRowBackground(theme.background)
            }
            .scrollContentBackgroundHidden()
            .frame(maxHeight: .infinity)
            Spacer()
        }
        .padding()
        .navigationTitle(String(localized: "Report post", comment: "Navigation title"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(String(localized: "Report.verb", comment: "Button to publish report"), systemImage: "checkmark") {
                    guard let account = account() else { return }
                    if account.isNC {
                        var report = EventMessageBuilder.makeReportEvent(pubkey: nrPost.pubkey, eventId: nrPost.id, type: reason, note: comment, includeProfile: reportWhat == "Profile+Profile")
                        report.publicKey = account.publicKey
                        report = report.withId()
                        RemoteSignerManager.shared.requestSignature(forEvent: report, usingAccount: account, whenSigned: { signedEvent in
                            Unpublisher.shared.publishNow(signedEvent)
                        })
                    }
                    else {
                        guard let signedReport = AccountsState.shared.loggedInAccount?.report(pubkey: nrPost.pubkey, eventId: nrPost.id, reportType: reason, note: comment, includeProfile: reportWhat == "Profile+Profile" ) else {
                            return
                        }
                        Unpublisher.shared.publishNow(signedReport)
                    }
                    dismiss()
                }
            }
        }
    }
}

import NavigationBackport

struct ReportPostSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            NBNavigationStack {
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    ReportPostSheet(nrPost: nrPost)
                }
            }
        }
    }
}
