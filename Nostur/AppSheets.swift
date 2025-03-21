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
}

struct WithAppSheets: ViewModifier {
    
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var loggedInAccount: LoggedInAccount
    @ObservedObject private var asm = AppSheetsModel.shared
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $asm.readOnlySheetVisible) {
                NRNavigationStack {
                    ReadOnlyAccountInformationSheet()
                        .presentationDetentsLarge()
                }
            }
            .sheet(item: $asm.askLoginInfo, content: { askLoginInfo in
                NRNavigationStack {
                    AskLoginSheet(askLoginInfo: askLoginInfo, account: loggedInAccount.account)
                        .presentationBackgroundCompat(themes.theme.background)
                        .presentationDetents250medium()
                }
            })
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
