//
//  PostMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/05/2023.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

struct PostMenu: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var la: LoggedInAccount
    public let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    @Environment(\.dismiss) private var dismiss
    private let NEXT_SHEET_DELAY = 0.05
    @State private var followToggles = false
    @State private var blockOptions = false
    @State private var pubkeysInPost: Set<String> = []
    
    @State private var showMultiFollowSheet = false
    @State private var showContactSubMenu = false
    @State private var showContactBlockSubMenu = false
    @State private var showPostDetailsSubMenu = false
    @State private var showPostShareSheet = false
    @State private var showRepublishSheet = false
    
    @State private var isOwnPost = false
    @State private var isFullAccount = false
    @State private var isFollowing = false
    @State private var showPinThisPostConfirmation = false
    
    init(nrPost: NRPost) {
        self.nrPost = nrPost
        self.nrContact = nrPost.contact
    }
    
    var body: some View {
        List {
            
            if isOwnPost && self.isFullAccount {
                Section {
                    // Delete button
                    Button(role: .destructive, action: {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                            sendNotification(.requestDeletePost, nrPost.id)
                        }
                    }) {
                        Label(String(localized:"Delete", comment:"Post context menu action to Delete a post"), systemImage: "trash")
                            .foregroundColor(theme.accent)
                    }
                    
                    Button(action: {
                        showPinThisPostConfirmation = true
                    }) {
                        Label("Pin to your profile", systemImage: "pin")
                            .foregroundColor(theme.accent)
                    }
                    .confirmationDialog(
                         Text("Pin this post"),
                         isPresented: $showPinThisPostConfirmation,
                         titleVisibility: .visible
                     ) {
                         Button("Pin") {
                             Task {
                                 try await pinToProfile(nrPost)
                                 try await addToHighlights(nrPost)
                             }
                         }
                     } message: {
                         Text("This will appear at the top of your profile and replace any previously pinned post.")
                     }
                    
                    Button(action: {
                        
                    }) {
                        Label("Add/remove from Highlights", systemImage: "star")
                            .foregroundColor(theme.accent)
                    }
                    
                    if nrPost.isRestricted {
                        Button {
                           showRepublishSheet = true
                        } label: {
                            Label(String(localized: "Republish to different relay(s)", comment: "Button to republish a post different relay(s)"), systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                }
                .listRowBackground(theme.background)
            }
            
            Section {
                if !isOwnPost {
                    self.followButton
                }
                
                Button(action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY + 0.35) { // Short delay freezes????
                        sendNotification(.addRemoveToListsheet, nrPost.contact)
                    }
                }) {
                    Label("Add/remove from Lists", systemImage: "person.2.crop.square.stack")
                        .foregroundColor(theme.accent)
                }
        
                if !isOwnPost {
                    Button(action: {
                        dismiss()
                        sendNotification(.clearNavigation)
                        sendNotification(.showingSomeoneElsesFeed, nrPost.contact)
                    }) {
                        Label {
                            Text("Show \(nrContact.anyName)'s feed", comment: "Menu button to show someone's feed")
                                .foregroundColor(theme.accent)
                        } icon: {
                            ObservedPFP(nrContact: nrContact, size: 20)
                        }
                    }
                }
            }
            .listRowBackground(theme.background)
            
            
            
            Section {
                Button(action: {
                    showContactBlockSubMenu = true
                }) {
                    Label("Block \(nrContact.anyName)", systemImage: "circle.slash")
                        .foregroundColor(theme.accent)
                }
                
                Button(action: {
                    dismiss()
                    L.og.debug("Mute conversation")
                    mute(eventId: nrPost.id, replyToRootId: nrPost.replyToRootId, replyToId: nrPost.replyToId)
                }) {
                    Label("Mute", systemImage: "bell.slash")
                        .foregroundColor(theme.accent)
                }
                
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.reportPost, nrPost)
                    }
                } label: {
                    Label(String(localized:"Report.verb", comment:"Post context menu action to Report a post or user"), systemImage: "flag")
                        .foregroundColor(theme.accent)
                }
            }
            .listRowBackground(theme.background)
            
            
            Button(action: {
                showPostShareSheet = true
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .foregroundColor(theme.accent)
            }
            .listRowBackground(theme.background)
            
            Button {
                dismiss()
                if let pn = Event.fetchEvent(id: nrPost.id, context: viewContext())?.privateNote {
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.editingPrivateNote, pn)
                    }
                }
                else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + NEXT_SHEET_DELAY) {
                        sendNotification(.newPrivateNoteOnPost, nrPost.id)
                    }
                }
            } label: {
                Label(String(localized:"Add private note to post", comment: "Post context menu button"), systemImage: "note.text")
                    .foregroundColor(theme.accent)
            }
            .listRowBackground(theme.background)

            Button(action: {
                showPostDetailsSubMenu = true
            }) {
                Label("Post details", systemImage: "info.circle")
                    .foregroundColor(theme.accent)
                
            }
            .listRowBackground(theme.background)
            
        }

        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        
        .onAppear {
            isOwnPost = nrPost.pubkey == la.pubkey
            self.isFullAccount = la.account.isFullAccount
        }
        
        .nbNavigationDestination(isPresented: $showMultiFollowSheet) {
            MultiFollowSheet(pubkey: nrPost.pubkey, name: nrPost.anyName, onDismiss: { dismiss() })
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure full screen usage (for bg)
                .background(theme.listBackground)
                .environment(\.theme, theme)
        }
        .nbNavigationDestination(isPresented: $showContactBlockSubMenu) {
            PostMenuBlockOptions(nrContact: nrPost.contact, onDismiss: { dismiss() })
                .environment(\.theme, theme)
        }
        .nbNavigationDestination(isPresented: $showContactSubMenu) {
            List {
                Button(role: .destructive, action: {
                    showContactBlockSubMenu = true
                }) {
                    Label("Block", systemImage: "square.and.arrow.up")
                }
                // Delete button
                Button(role: .destructive, action: {
                    
                }) {
                    Label("Follow", systemImage: "trash")
                }
            }
            
        }
        .nbNavigationDestination(isPresented: $showPostShareSheet) {
            PostMenuShareSheet(nrPost: nrPost, onDismiss: { dismiss() })
        }
        .nbNavigationDestination(isPresented: $showPostDetailsSubMenu) {
            PostDetailsMenuSheet(nrPost: nrPost, onDismiss: { dismiss() })
                .environmentObject(la)
        }
        
        .nbNavigationDestination(isPresented: $showRepublishSheet) {
            RepublishRestrictedPostSheet(nrPost: nrPost, onDismiss: { dismiss() })
                .environmentObject(la)
        }
        
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { dismiss() }) {
                    Text("Done")
                }
            }
        }
        
    }
    
    @ViewBuilder
    private var followButton: some View {
        Button(action: {
            guard Nostur.isFullAccount() else {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05)  {
                    showReadOnlyMessage()
                }
                return
            }
            dismiss()
            if isFollowing {
                la.unfollow(nrPost.pubkey)
                isFollowing = false
            }
            else {
                la.follow(nrPost.pubkey)
            }
        }) {
            if isFollowing {
                Label(String(localized:"Unfollow \(nrPost.anyName)", comment: "Post context menu button to Unfollow (name)"), systemImage: "person.badge.minus")
                    .foregroundColor(theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading) // Needed do List row tap area doesn't cover long tap
                    .contentShape(Rectangle())
            }
            else {
                Label(String(localized:"Follow \(nrPost.anyName)", comment: "Post context menu button to Follow (name)"), systemImage: "person.badge.plus")
                    .foregroundColor(theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading) // Needed do List row tap area doesn't cover long tap
                    .contentShape(Rectangle())
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    showMultiFollowSheet = true
                }
        )
        .onAppear {
            isFollowing = Nostur.isFollowing(nrPost.pubkey)
        }
    }
}

let NEXT_SHEET_DELAY = 0.05

struct PostMenuButton: View {
    @Environment(\.theme) private var theme
    var nrPost: NRPost
    
    var body: some View {
        Image(systemName: "ellipsis")
            .fontWeightBold()
            .foregroundColor(theme.footerButtons)
            .padding(.leading, 15)
            .padding(.bottom, 14)
            .padding(.top, 10)
            .padding(.trailing, 10)
            .contentShape(Rectangle())
            .padding(.top, -10)
            .padding(.trailing, -10)
            .highPriorityGesture(
                TapGesture()
                    .onEnded { _ in
                        sendNotification(.showNoteMenu, nrPost)
                    }
            )
    }
}

#Preview("Post Menu") {
    PreviewContainer {
        NBNavigationStack {
            PostMenu(nrPost: testNRPost())
                .environment(\.theme, Themes.GREEN)
        }
    }
}

#Preview("Post Menu Button") {
    PreviewContainer {
        NBNavigationStack {
            PostMenuButton(nrPost: testNRPost())
                .withSheets()
                .environment(\.theme, Themes.GREEN)
        }
    }
}
