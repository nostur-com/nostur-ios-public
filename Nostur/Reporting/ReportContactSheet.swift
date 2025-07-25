//
//  ReportContactSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/04/2023.
//

import SwiftUI

struct ReportContactSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) var dismiss
    let reportContact: ReportContact
    @State var reason = ReportType.impersonation
    @State var comment:String = ""
    
    var body: some View {
        VStack {
            Box {
                NRContactSearchResultRow(nrContact: reportContact.nrContact)
            }
            .padding(10)
            .background(theme.listBackground)
            .disabled(true)
            .opacity(0.9)
                
            
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
                    guard let account = account() else { return }
                    if account.isNC {
                        var report = EventMessageBuilder.makeReportContact(pubkey: reportContact.nrContact.pubkey, type: reason, note: comment)
                        
                        report.publicKey = account.publicKey
                        report = report.withId()
                        
                        NSecBunkerManager.shared.requestSignature(forEvent: report, usingAccount: account, whenSigned: { signedEvent in
                            Unpublisher.shared.publishNow(signedEvent)
                        })
                    }
                    else {
                        guard let signedReport = AccountsState.shared.loggedInAccount?.reportContact(pubkey: reportContact.nrContact.pubkey, reportType: reason, note: comment) else {
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

struct ReportContactSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            NBNavigationStack {
                if let nrContact = PreviewFetcher.fetchNRContact() {
                    ReportContactSheet(reportContact: ReportContact(nrContact: nrContact))
                }
            }
        }
    }
}
