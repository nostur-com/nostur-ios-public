//
//  ReportPostSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/04/2023.
//

import SwiftUI

struct ReportPostSheet: View {
    @Environment(\.dismiss) var dismiss
    let nrPost:NRPost
    @State var reason = ReportType.spam
    @State var comment:String = ""
    @State var reportWhat = "Post" // to also report the profile, not just the post
    
    var body: some View {
        VStack {
            ScrollView {
                PostRowDeletable(nrPost: nrPost, hideFooter: true, missingReplyTo: true)
                    .disabled(true)
                    .roundedBoxShadow()
                    .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING)
                    .padding(.vertical, 10)
                    .overlay(
                        Rectangle().opacity(0.02)
                            .onTapGesture {
                                
                            }
                    )
                    .padding(10)
                    .opacity(0.8)
                    .background(Color("ListBackground"))
            }
            .frame(maxHeight: 200)
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
            }
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
                Button(String(localized: "Report.verb", comment: "Button to publish report")) {
                    guard let account = NosturState.shared.account else { return }
                    if account.isNC {
                        var report = EventMessageBuilder.makeReportEvent(pubkey: nrPost.pubkey, eventId: nrPost.id, type: reason, note: comment, includeProfile: reportWhat == "Profile+Profile")
                        report.publicKey = account.publicKey
                        report = report.withId()
                        NosturState.shared.nsecBunker?.requestSignature(forEvent: report, whenSigned: { signedEvent in
                            Unpublisher.shared.publishNow(signedEvent)
                        })
                    }
                    else {
                        guard let signedReport = NosturState.shared.report(nrPost.mainEvent, reportType: reason, note: comment, includeProfile: reportWhat == "Profile+Profile" ) else {
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

struct ReportPostSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            NavigationStack {
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    ReportPostSheet(nrPost: nrPost)
                }
            }
        }
    }
}
