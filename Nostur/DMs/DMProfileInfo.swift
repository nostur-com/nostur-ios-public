//
//  DMProfileInfo.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/12/2025.
//

import SwiftUI
import NostrEssentials

// Copy paste from ProfileView
struct DMProfileInfo: View {
    @StateObject private var vm = ProfileViewModel()
    @StateObject private var lastSeenVM = LastSeenViewModel()
    
    @ObservedObject public var nrContact: NRContact
    
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID

    @EnvironmentObject private var la: LoggedInAccount
    
    @ObservedObject private var settings: SettingsStore = .shared

    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        VStack(alignment: .center) {
            ObservedPFP(nrContact: nrContact, size: 100)

            HStack(spacing: 0) {
                Text("\(nrContact.anyName) ")
                    .font(.title)
                    .fontWeightBold()
                    .lineLimit(1)
                PossibleImposterLabelView2(nrContact: nrContact)
                if nrContact.similarToPubkey == nil && nrContact.nip05verified, let nip05 = nrContact.nip05 {
                    NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly?.lowercased())
                        .layoutPriority(3)
                }
            }
            
            if let fixedName = nrContact.fixedName, fixedName != nrContact.anyName {
                HStack {
                    Text("Previously known as: \(fixedName)").font(.caption).foregroundColor(.primary)
                        .lineLimit(1)
                    Image(systemName: "multiply.circle.fill")
                        .onTapGesture {
                            nrContact.setFixedName(nrContact.anyName)
                        }
                }
            }
            
            HStack {
                CopyableTextView(text: vm.npub)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
                
                if let mainContact = Contact.fetchByPubkey(nrContact.pubkey, context: viewContext())  {
                    ContactPrivateNoteToggle(contact: mainContact)
                }
                Menu {
                    Button {
                        UIPasteboard.general.string = vm.npub
                    } label: {
                        Label(String(localized:"Copy npub", comment:"Menu action"), systemImage: "doc.on.clipboard")
                    }
                    Button {
                        sendNotification(.addRemoveToListsheet, nrContact)
                    } label: {
                        Label(String(localized:"Add/Remove from Lists", comment:"Menu action"), systemImage: "person.2.crop.square.stack")
                    }
                    
                    if vm.isBlocked {
                        Button(action: {
                            unblock(pubkey: nrContact.pubkey)
                            vm.isBlocked = false // TODO: Add listener on vm instead of this
                        }) {
                            Label("Unblock", systemImage: "circle.slash")
                        }
                    }
                    else {
                        Button {
                            block(pubkey: nrContact.pubkey, name: nrContact.anyName)
                            vm.isBlocked = true // TODO: Add listener on vm instead of this
                        } label: {
                            Label(
                                String(localized:"Block \(nrContact.anyName)", comment: "Menu action"), systemImage: "circle.slash")
                        }
                    }
                    Button {
                        sendNotification(.reportContact, ReportContact(nrContact: nrContact))
                    } label: {
                        Label(String(localized:"Report \(nrContact.anyName)", comment:"Menu action"), systemImage: "flag")
                    }
                    
                    Button {
                        vm.copyProfileSource(nrContact)
                    } label: {
                        Label(String(localized:"Copy profile source", comment:"Menu action"), systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .fontWeightBold()
                        .padding(5)
                }
            }
            
            if (vm.isFollowingYou) {
                Text("Follows you", comment: "Label shown when someone follows you").font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary)
                    .opacity(0.7)
                    .cornerRadius(13)
                    .offset(y: -4)
            }
            
            Text(verbatim: lastSeenVM.lastSeen ?? "Last seen:")
                .font(.caption).foregroundColor(.primary)
                .lineLimit(1)
                .opacity(lastSeenVM.lastSeen != nil ? 1.0 : 0)
            
            HStack {
                Spacer()
                if nrContact.anyLud {
                    ProfileLightningButton(nrContact: nrContact)
                }
                
                FollowButton(pubkey: nrContact.pubkey)
                    .buttonStyle(.borderless)
                Spacer()
            }
            
            NRTextDynamic("\(String(nrContact.about ?? ""))\n")

            FollowedBy(pubkey: nrContact.pubkey, alignment: .center, showZero: true)
         //
        }
        .padding([.top, .leading, .trailing], 10.0)
        .onTapGesture { }
        

        .onAppear {
            vm.load(nrContact, loadLess: true)
            lastSeenVM.checkLastSeen(nrContact.pubkey)
        }
        
        .task {
            try? await Task.sleep(nanoseconds: 5_100_000_000) // Try .SEARCH relays if we don't have info
            if nrContact.metadata_created_at == 0 {
                nxReq(Filters(authors: [nrContact.pubkey], kinds: [0]), subscriptionId: UUID().uuidString, relayType: .SEARCH)
            }
        }
    }

}
