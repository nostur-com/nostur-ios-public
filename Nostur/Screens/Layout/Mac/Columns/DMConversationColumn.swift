//
//  DMConversationColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/12/2025.
//

import SwiftUI
import NavigationBackport

struct DMConversationColumn: View {
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.theme) private var theme
    
    public let participantPs: Set<String>
    public let ourAccountPubkey: String
    @Binding var navPath: NBNavigationPath
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        ZStack {
            theme.listBackground // needed to give this ZStack and parents size, else weird startup animation sometimes
            // FOLLOWING
            Text("Conversation for \(participantPs) - ourAccountPubkey: \(ourAccountPubkey) here")
        }
        .background(theme.listBackground)
    }
    
//    @ToolbarContentBuilder
//    private func newPostButton(_ config: NXColumnConfig) -> some ToolbarContent {
//        ToolbarItem(placement: .navigationBarTrailing) {
//            if case .picture(_) = config.columnType { // No settings for .picture
//                Button("Post New Photo", systemImage: "square.and.pencil") {
//                    guard isFullAccount() else { showReadOnlyMessage(); return }
//                    AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .picture)
//                }
//            }
//            
//            if case .yak(_) = config.columnType { // No settings for .yak
//                Button("New Voice Message", systemImage: "square.and.pencil") {
//                    guard isFullAccount() else { showReadOnlyMessage(); return }
//                    AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .shortVoiceMessage)
//                }
//            }
//        }
//    }
//    
//    @ToolbarContentBuilder
//    private func settingsButton(_ config: NXColumnConfig) -> some ToolbarContent {
//        ToolbarItem(placement: .navigationBarTrailing) {
//            if case .vine(_) = config.columnType { // No settings for .vine
//               
//            }
//            else { // Settings on every feed type except .vine
//                Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
//                    AppSheetsModel.shared.feedSettingsFeed = config.feed
//                }
//            }
//        }
//    }
}
