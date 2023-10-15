//
//  FooterConfigurator.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/10/2023.
//

import SwiftUI

struct FooterConfigurator: View {
    
    @Binding public var footerButtons:String
    @ObservedObject private var ss:SettingsStore = .shared
    
    var body: some View {
        Form(content: {
            
            Section(content: {
                TextField("Footer buttons", text: $footerButtons)
                    .onChange(of: footerButtons, perform: { newValue in
                        if newValue.count > ViewModelCache.BUTTONS_PER_ROW {
                            footerButtons = filterT(String(newValue.prefix(ViewModelCache.BUTTONS_PER_ROW)))
                        }
                        else {
                            let filteredButtons = filterT(footerButtons)
                            if filteredButtons != footerButtons {
                                footerButtons = filteredButtons
                            }
                        }
                    })
            }, header: {
                Text("Button configurator", comment: "Heading when entering Report details")
            }, footer: {
                Text("Configure the reaction buttons for each post. You can also change the position or remove buttons you don't need.", comment: "Informational message")
            })
            
            Section(content: {
                if !ss.fullWidthImages {
                    HStack(spacing: 0) {
                        CustomizablePreviewFooterFragmentView()
                            .padding(.horizontal, DIMENSIONS.POST_ROW_PFP_DIAMETER/2)
                            .disabled(true)
                    }
                    .padding([.horizontal], -10)
                }
                else {
                    CustomizablePreviewFooterFragmentView()
                        .disabled(true)
                        .padding([.horizontal], -10)
                }
            }, header: {
                Text("Preview", comment: "Heading when entering Report details")
            })
            
            Button("Load default", action: {
                footerButtons = "💬🔄+🔖"
            })
            
            Button("Load preset 1", action: {
                footerButtons = "💬🔄+🫂💯🔖"
            })
            
            Button("Load preset 2", action: {
                footerButtons = "💬🔄+🔥🍿🔖"
            })
            
            Button("Load preset 3", action: {
                footerButtons = "🫂💯🔥🤯🔖"
            })
            
            Button("Load preset 4", action: {
                footerButtons = "+❤️💜💙🧡💚🖤"
            })
        })
    }
}

struct FooterConfiguratorTester: View {
    @State private var footerButtons = "💬🔄+💯🔥🔖"

    var body: some View {
        FooterConfigurator(footerButtons: $footerButtons)
    }
}

#Preview("FooterConfigurator") {
    PreviewContainer {
        FooterConfiguratorTester()
    }
}


func filterT(_ string:String) -> String {
    return string.filter {
        $0 == "+" || isEmoji($0)
    }
}

// check if character is an emoji
// includes emoticons and variations
func isEmoji(_ character: Character) -> Bool {
    return character.isEmoji
}

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji
    }
}
