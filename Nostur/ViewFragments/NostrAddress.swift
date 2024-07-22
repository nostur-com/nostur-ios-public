//
//  NostrAddress.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/09/2023.
//

import SwiftUI

struct NostrAddress: View {
    @EnvironmentObject private var themes:Themes

    public var nip05: String
    public var shortened = false
    
    var domainPart:String {
        String(nip05.split(separator: "@", maxSplits: 1).last ?? "")
    }
    
    var localPart:String {
        String(nip05.split(separator: "@", maxSplits: 1).first ?? "")
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if !shortened && localPart != "_" {
                Text(localPart)
            }
            Image(systemName: "at.circle.fill")
                .foregroundColor(themes.theme.accent)
                .offset(y: 1)
            Text(domainPart)
        }
        .foregroundColor(themes.theme.accent)
        .lineLimit(1)
    }
}

struct NostrAddress_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Group {
                NostrAddress(nip05: "fabian@nostur.com", shortened: true)
                NostrAddress(nip05: "fabian@nostur.com")
                NostrAddress(nip05: "nostur.com", shortened: true)
                NostrAddress(nip05: "nostur.com")
                NostrAddress(nip05: "_@nostur.com", shortened: true)
                NostrAddress(nip05: "_@nostur.com")
            }
            
            Divider()
            
            // handle incorrect entries
            Group {
                NostrAddress(nip05: "@_@nostur.com", shortened: true)
                NostrAddress(nip05: "nostur@com", shortened: true)
                NostrAddress(nip05: "@@nostur.com", shortened: true)
                NostrAddress(nip05: "x@x@nostur.com", shortened: true)
                NostrAddress(nip05: "x@x@nostur.com", shortened: true)
            }
            
            Divider()
            
            // handle incorrect entries
            Group {
                NostrAddress(nip05: "fabian@_@nostur.com")
                NostrAddress(nip05: "fabian@nostur@com")
                NostrAddress(nip05: "fabian@@nostur.com")
                NostrAddress(nip05: "fabian@x@nostur.com")
                NostrAddress(nip05: "fabian@x@nostur.com")
            }
        }
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
            .environmentObject(Themes.default)
    }
}
