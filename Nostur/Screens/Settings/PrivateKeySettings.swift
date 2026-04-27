//
//  PrivateKeySettings.swift
//  Nostur
//
//  Created by Codex on 27/04/2026.
//

import SwiftUI
import NavigationBackport

struct PrivateKeySettings: View {
    @EnvironmentObject private var la: LoggedInAccount
    @State private var isPrivateKeyRevealed = false

    private var nsec: String? {
        la.account.nsec
    }

    var body: some View {
        NXForm {
            Section {
                Text("Your private key controls your account. Never share it with anyone. Anyone with this key can fully access your account and post as you.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section {
                Button {
                    isPrivateKeyRevealed.toggle()
                } label: {
                    Label(isPrivateKeyRevealed ? "Hide private key" : "Reveal private key", systemImage: isPrivateKeyRevealed ? "eye.slash" : "eye")
                }

                if let nsec {
                    Button {
                        UIPasteboard.general.string = nsec
                        sendNotification(.anyStatus, (String(localized: "Private key copied to clipboard", comment: "Notification shown after user tapped to copy"), "COPYKEYS"))
                    } label: {
                        Label("Copy private key", systemImage: "doc.on.doc")
                    }
                }
                else {
                    Text("Private key not available for this account.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if isPrivateKeyRevealed, let nsec {
                Section(header: Text("Private key")) {
                    Text(nsec)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Private key")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            AnyStatus(filter: "COPYKEYS")
                .opacity(0.85)
        }
    }
}

#Preview {
    PreviewContainer {
        NBNavigationStack {
            PrivateKeySettings()
        }
    }
}
