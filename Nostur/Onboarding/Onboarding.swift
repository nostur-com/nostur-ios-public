import SwiftUI

struct Onboarding: View {
    @EnvironmentObject var ns:NosturState
    @AppStorage("did_accept_terms") var didAcceptTerms = false // TODO: DONT FORGET TO SET TO FALSE ON APP STORE SUBMIT
    
    var body: some View {
        let _ = Self._printChanges()
        if (!didAcceptTerms) {
            TermsAndConditions()
        }
        else {
            NavigationStack {
                WelcomeSheet(offerTryOut: true)
                    .interactiveDismissDisabled()
                    .withNavigationDestinations()
            }
        }
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        Onboarding()
            .withPreviewEnvironment()
    }
}
