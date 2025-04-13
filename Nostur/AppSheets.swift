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
    
    // Workaround because .sheet / .fullScreenCover has some issues with NavigationBackPort where dismiss() doesn't work
    @MainActor func dismiss() {
        readOnlySheetVisible = false
        askLoginInfo = nil
        feedPreviewSheetInfo = nil
    }
}

struct WithAppSheets: ViewModifier {
    
    @ObservedObject private var themes: Themes = .default
    @EnvironmentObject private var loggedInAccount: LoggedInAccount
    @ObservedObject private var asm = AppSheetsModel.shared
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $asm.readOnlySheetVisible) {
                NRSheetNavigationStack {
                    ReadOnlyAccountInformationSheet()
                        .presentationDetentsLarge()
                }
            }
            .sheet(item: $asm.askLoginInfo, content: { askLoginInfo in
                NBNavigationStack {
                    AppEnvironment {
                        AskLoginSheet(askLoginInfo: askLoginInfo, account: loggedInAccount.account)
                    }
                }
                .nbUseNavigationStack(.never)
                .presentationDetents250medium()
                .presentationBackgroundCompat(Themes.default.theme.listBackground)
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
