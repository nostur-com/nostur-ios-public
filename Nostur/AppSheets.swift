//
//  AppSheets.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import SwiftUI
import NavigationBackport

class AppSheetsModel: ObservableObject {
    
    static let shared = AppSheetsModel()
    
    private init() {}
    
    @Published var readOnlySheetVisible: Bool = false
    @Published var askLoginInfo: AskLoginInfo? = nil
    @Published var postMenuContext: PostMenuContext? = nil
    @Published var relayFeedPreviewSheetInfo: RelayFeedPreviewInfo? = nil
    @Published var feedPreviewSheetInfo: FeedPreviewInfo? = nil
    @Published var addContactsToListInfo: AddContactsToListInfo? = nil
    @Published var emojiRR: EmojiPickerFor? = nil
    @Published var feedSettingsFeed: CloudFeed? = nil
    @Published var showReplyToSheet: ReplyTo? = nil
    
    // Workaround because .sheet / .fullScreenCover has some issues with NavigationBackPort where dismiss() doesn't work
    @MainActor func dismiss() {
        readOnlySheetVisible = false
        askLoginInfo = nil
        postMenuContext = nil
        feedPreviewSheetInfo = nil
        relayFeedPreviewSheetInfo = nil
        addContactsToListInfo = nil
        emojiRR = nil
        feedSettingsFeed = nil
        showReplyToSheet = nil
    }
}

struct WithAppSheets: ViewModifier {
    
    public var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var asm = AppSheetsModel.shared
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $asm.addContactsToListInfo, content: { info in
                NRSheetNavigationStack {
                    AddContactsToListSheet(preSelectedContactPubkeys: info.pubkeys, rootDismiss: { dismiss() })
                        .presentationDetentsLarge()
                }
                .environmentObject(la)
            })
            .sheet(isPresented: $asm.readOnlySheetVisible) {
                NRSheetNavigationStack {
                    ReadOnlyAccountInformationSheet()
                        .presentationDetentsLarge()
                }
                .environmentObject(la)
            }
            .sheet(item: $asm.askLoginInfo, content: { askLoginInfo in
                NBNavigationStack { // Note: Can't use NRSheetNavigationStack here but forgot why
                    AppEnvironment(la: la) {
                        AskLoginSheet(askLoginInfo: askLoginInfo, account: la.account)
                    }
                }
                .nbUseNavigationStack(.never)
                .presentationDetents250medium()
                .presentationBackgroundCompat(theme.listBackground)
            })
        
            .sheet(item: $asm.postMenuContext, content: { postMenuContext in
                NRSheetNavigationStack {
                    PostMenu(postMenuContext: postMenuContext)
                }
                .environmentObject(la)
            })
        
            .sheet(item: $asm.feedSettingsFeed, content: { feed in
                NRSheetNavigationStack {
                    FeedSettings(feed: feed)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close", systemImage: "xmark") {
                                    asm.feedSettingsFeed = nil
                                }
                            }
                        }
                }
                .environmentObject(la)
            })
        
            .sheet(item: $asm.showReplyToSheet, content: { replyToInfo in
                NRSheetNavigationStack {
                    CommentsDetail(nrPost: replyToInfo.nrPost)
                        .navigationTitle("Comments")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close", systemImage: "xmark") {
                                    asm.showReplyToSheet = nil
                                }
                            }
                        }
                }
                .environmentObject(la)
            })
        
        
            // List/Follow Pack feed preview
            .fullScreenCover(item: $asm.feedPreviewSheetInfo) { feedPreviewSheetInfo in
                NRSheetNavigationStack {
                    ZStack(alignment: .center) {
                        if !IS_IPHONE {
                            Color.black.opacity(0.5)
                        }
                        AvailableWidthContainer {
                            FollowPackPreviewSheet(nrPost: feedPreviewSheetInfo.nrPost, config: feedPreviewSheetInfo.config)
                        }
                        .frame(maxWidth: !IS_IPHONE ? 560 : .infinity) // Don't make very wide feed on Desktop
                    }
                }
                .environmentObject(la)
            }
        
            // New relay feed configure connection and preview
            .fullScreenCover(item: $asm.relayFeedPreviewSheetInfo) { relayFeedPreviewSheetInfo in
                NRSheetNavigationStack {
                    
                    ZStack(alignment: .center) {
                        if !IS_IPHONE {
                            Color.black.opacity(0.5)
                        }
                        RelayPreviewFeedSheet(prefillAddress: relayFeedPreviewSheetInfo.relayUrl)
                            .frame(maxWidth: !IS_IPHONE ? 560 : .infinity) // Don't make very wide feed on Desktop
                    }
                }
                .environment(\.theme, theme)
                .environmentObject(la)
            }
        
            .background {
                MCEmojiPickerRepresentableController(
                    presentationMode: Binding(
                        get: { asm.emojiRR != nil ? .sheet : .none },
                        set: { if $0 != .sheet { asm.emojiRR = nil  } }
                    ),
                    selectedEmoji: Binding(get: {
                        if let emojiRR = asm.emojiRR {
                            return emojiRR.selectedEmoji.wrappedValue
                        }
                        return ""
                    }, set: { newValue in
                        if let emojiRR = asm.emojiRR {
                            emojiRR.selectedEmoji.wrappedValue = newValue
                        }
                    }),
                )
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func withAppSheets(la: LoggedInAccount) -> some View {
        modifier(WithAppSheets(la: la))
    }
}

func showReadOnlyMessage() {
    AppSheetsModel.shared.readOnlySheetVisible = true
}
