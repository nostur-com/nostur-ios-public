//
//  TermsAndConditions.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/04/2023.
//

import SwiftUI

struct TermsAndConditions: View {
    @AppStorage("did_accept_terms") var didAcceptTerms = false
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment:.leading) {
                    Text("**Terms and Conditions**\n", comment: "Terms and conditions heading")
                        .hCentered()

                    Text(#"Please read these Terms and Conditions ("Terms", "Terms and Conditions") carefully before using Nostur (the "App") operated by the independent developer ("Developer")."#, comment:"Terms and conditions paragraph")
                    
                    Text("""
Last updated: May 27th, 2023
    
Your access to and use of the App is conditioned upon your acceptance of and compliance with these Terms. These Terms apply to all users of the App.

By accessing or using the App, you agree to be bound by these Terms. If you disagree with any part of the terms, then you do not have permission to access the App.

Accounts
When you create an account with the App, you are responsible for maintaining the confidentiality of your account keys, as well as restricting access to your device. You agree to accept responsibility for any and all activities or actions that occur under your account.

Content
The App allows you to access, read, and post content through connecting to relays. You are responsible for the content that you post or access through the App, including its legality, reliability, and appropriateness.

By posting content through the App, you represent and warrant that the content is yours (you own it) and/or you have the right to use it, and that the posting of your content through the App does not violate the privacy rights, publicity rights, copyrights, contract rights, or any other rights of any person or entity.

Prohibited Activities
You agree not to use the App for any illegal, harmful, or offensive activities, including but not limited to:

Engaging in harassment, bullying, or any form of intimidation
Distributing or promoting sexually explicit or pornographic material
Promoting hate speech, racism, or discrimination of any kind
Infringing upon the intellectual property rights of others
Engaging in any form of fraud, phishing, or unauthorized data collection
Intellectual Property
The App and its original content (excluding Content provided by users), features, and functionality are and will remain the exclusive property of the Developer. The App is protected by copyright, trademark, and other laws of the United States and foreign countries. Any trademarks and trade dress may not be used in connection with any product or service without the prior written consent of the Developer.

Limitation of Liability
In no event shall the Developer be liable for any indirect, incidental, special, consequential, or punitive damages, including without limitation, loss of profits, data, use, goodwill, or other intangible losses, resulting from (i) your access to or use of or inability to access or use the App; (ii) any conduct or content of any third party on the App; (iii) any content obtained from the App; and (iv) unauthorized access, use, or alteration of your transmissions or content, whether based on warranty, contract, tort (including negligence), or any other legal theory, whether or not the Developer has been informed of the possibility of such damage, and even if a remedy set forth herein is found to have failed of its essential purpose.

Privacy Policy
Nostur does not collect information about you. The app stores information that you provide about your nostr profile, which can be anything you choose to share or not. The posts and content you share from Nostur are sent out to public relays so anyone can view those and Nostur stores this on your device so you can always view it yourself.
The app uses the following external services:
Tenor: for inluding animated GIFs in your posts
Image upload services: For including images in your posts. You can opt out to using these services by not including images or GIFs in your posts and not uploading a profile picture or banner in the app.

For any questions, please contact feedback@nostur.com.
""", comment: "Terms and conditions")
                }
                .padding()
        }
            
            Button(String(localized:"Accept", comment: "Button to accept terms and conditions")) {
                didAcceptTerms = true
                if !NRState.shared.activeAccountPublicKey.isEmpty {
                    NRState.shared.onBoardingIsShown = false
                }
            }
        }
    }
}

struct TermsAndConditions_Previews: PreviewProvider {
    static var previews: some View {
        TermsAndConditions()
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
