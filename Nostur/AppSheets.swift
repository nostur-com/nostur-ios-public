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
    @Published var feedPreviewSheetInfo: FeedPreviewInfo? = nil
    @Published var addContactsToListInfo: AddContactsToListInfo? = nil
    @Published var emojiRR: EmojiPickerFor? = nil
    
    // Workaround because .sheet / .fullScreenCover has some issues with NavigationBackPort where dismiss() doesn't work
    @MainActor func dismiss() {
        readOnlySheetVisible = false
        askLoginInfo = nil
        feedPreviewSheetInfo = nil
        addContactsToListInfo = nil
        emojiRR = nil
    }
}

struct WithAppSheets: ViewModifier {
    
    @Environment(\.theme) private var theme
    @EnvironmentObject private var loggedInAccount: LoggedInAccount
    @ObservedObject private var asm = AppSheetsModel.shared
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $asm.addContactsToListInfo, content: { info in
                NRSheetNavigationStack {
                    AddContactsToListSheet(preSelectedContactPubkeys: info.pubkeys)
                        .presentationDetentsLarge()
                }
                .environmentObject(loggedInAccount)
            })
            .sheet(isPresented: $asm.readOnlySheetVisible) {
                NRSheetNavigationStack {
                    ReadOnlyAccountInformationSheet()
                        .presentationDetentsLarge()
                }
                .environmentObject(loggedInAccount)
            }
            .sheet(item: $asm.askLoginInfo, content: { askLoginInfo in
                NBNavigationStack { // Note: Can't use NRSheetNavigationStack here but forgot why
                    AppEnvironment(la: loggedInAccount) {
                        AskLoginSheet(askLoginInfo: askLoginInfo, account: loggedInAccount.account)
                    }
                }
                .nbUseNavigationStack(.never)
                .presentationDetents250medium()
                .presentationBackgroundCompat(theme.listBackground) // TODO: Test login sheet
            })
            .fullScreenCover(item: $asm.feedPreviewSheetInfo) { feedPreviewSheetInfo in
                NRSheetNavigationStack {
                    ZStack(alignment: .center) {
                        if !IS_IPHONE {
                            Color.black.opacity(0.5)
                        }
                        AvailableWidthContainer {
                            FeedPreviewSheet(nrPost: feedPreviewSheetInfo.nrPost, config: feedPreviewSheetInfo.config)
                        }
                        .frame(maxWidth: !IS_IPHONE ? 560 : .infinity) // Don't make very wide feed on Desktop
                    }
                }
                .environmentObject(loggedInAccount)
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
    func withAppSheets() -> some View {
        modifier(WithAppSheets())
    }
}

func showReadOnlyMessage() {
    AppSheetsModel.shared.readOnlySheetVisible = true
}
