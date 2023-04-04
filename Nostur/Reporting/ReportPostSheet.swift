//
//  ReportPostSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/04/2023.
//

import SwiftUI

struct ReportPostSheet: View {
    @Environment(\.dismiss) var dismiss
    let vPost:VPost
    @State var reason = ReportType.spam
    @State var comment:String = ""
    
    var body: some View {
        VStack {
            ScrollView {
                NoteRow(vPost: vPost, hideFooter: true)
                    .disabled(true)
                    .opacity(0.8)
                    .boxShadow()
            }
            .frame(maxHeight: 200)
            .clipped()
            
            Form {
                Section(header: Text("Report Information"), footer: VStack {
                    Text("Your report is public, other users can use your report to prevent this kind of content")
                }) {
                    Picker(selection: $reason, label: Text("Reason")) {
                        Text("Spam").tag(ReportType.spam)
                        Text("Impersonation").tag(ReportType.impersonation)
                        Text("Nudity").tag(ReportType.nudity)
                        Text("Profanity").tag(ReportType.profanity)
                        Text("Illegal content").tag(ReportType.illegal)
                    }
                        
                    TextField("Extra information", text: $comment)
                }
            }
            .frame(maxHeight: .infinity)
            Spacer()
        }
        .padding()
        .navigationTitle("Report post")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Report") {
                    guard let signedReport = NosturState.shared.report(vPost.event, reportType: reason, note: comment) else {
                        return
                    }
                    Unpublisher.shared.publishNow(signedReport)
                    dismiss()
                }
            }
        }
    }
}

struct ReportPostSheet_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            if let vPost = PreviewFetcher.fetchVPost() {
                ReportPostSheet(vPost: vPost)
            }
        }
        .withPreviewEnvironment()
    }
}
