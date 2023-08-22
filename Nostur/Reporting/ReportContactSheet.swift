//
//  ReportContactSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/04/2023.
//

import SwiftUI

struct ReportContactSheet: View {
    @Environment(\.dismiss) var dismiss
    let contact:Contact
    @State var reason = ReportType.impersonation
    @State var comment:String = ""
    
    var body: some View {
        VStack {
            ContactSearchResultRow(contact: contact)
                .padding()
                .disabled(true)
                .opacity(0.8)
                .roundedBoxShadow()
                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING)
                .padding(.vertical, 10)
            
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
                        
                    TextField(String(localized:"Extra information", comment: "Label for report field to give extra information"), text: $comment)
                }
            }
            Spacer()
        }
        .padding()
        .navigationTitle(String(localized: "Report person", comment: "Navigation title"))
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
                        var report = EventMessageBuilder.makeReportContact(pubkey: contact.pubkey, type: reason, note: comment)
                        
                        report.publicKey = account.publicKey
                        report = report.withId()
                        
                        NosturState.shared.nsecBunker?.requestSignature(forEvent: report, whenSigned: { signedEvent in
                            Unpublisher.shared.publishNow(signedEvent)
                        })
                    }
                    else {
                        guard let signedReport = NosturState.shared.reportContact(pubkey: contact.pubkey, reportType: reason, note: comment) else {
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

struct ReportContactSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            NavigationStack {
                if let contact = PreviewFetcher.fetchContact() {
                    ReportContactSheet(contact: contact)
                }
            }
        }
    }
}
