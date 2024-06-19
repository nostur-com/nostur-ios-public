//
//  PostAccountSwitcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/08/2023.
//

import SwiftUI

// TODO: .fanOutDirection doesn't work well yet so only use .bottom for now
struct InlineAccountSwitcher: View, Equatable {
    static func == (lhs: InlineAccountSwitcher, rhs: InlineAccountSwitcher) -> Bool {
        lhs.activeAccount == rhs.activeAccount //&& lhs.accounts.count == rhs.accounts.count
    }
    
    public var activeAccount: CloudAccount
    public var onChange: (CloudAccount) -> ()
    public var size: CGFloat = 50.0
    public var fanOutDirection: Direction = .bottom
    
    @State private var expanded = false
    
    @State private var accounts: [CloudAccount] = []
    
    private var accountsSorted: [CloudAccount] {
        accounts
            .sorted(by: {
                $0.lastLoginAt > $1.lastLoginAt
            })
            .sorted(by: {
                $0 == activeAccount && $1 != activeAccount
            })
    }
    
    @ViewBuilder
    private var bottom: some View {
        VStack(spacing: 2) {
            ForEach(accountsSorted.indices, id:\.self) { index in
                PFP(pubkey: accountsSorted[index].publicKey, account: accountsSorted[index], size: size)
                    .onTapGesture {
                        accountTapped(accountsSorted[index])
                    }
                    .opacity(index == 0 || expanded ? 1.0 : 0.2)
                    .zIndex(-Double(index))
                    .offset(y: expanded || (index == 0) ? 0 : (Double(index) * -(size - 2)))
                    .animation(.easeOut(duration: 0.2), value: expanded)
                    .id(accountsSorted[index].publicKey) // sorting index and view identity (publicKey) is different!
            }
        }
        .fixedSize()
    }
    
    @ViewBuilder
    private var top: some View {
        VStack(spacing: 2) {
            ForEach(accountsSorted.indices, id:\.self) { index in
                PFP(pubkey: accountsSorted[index].publicKey, account: accountsSorted[index], size: size)
                    .onTapGesture {
                        accountTapped(accountsSorted[index])
                    }
                    .opacity(index == 0 || expanded ? 1.0 : 0.2)
                    .zIndex(-Double(index))
                    .offset(y: (expanded || (index == 0)) ? (Double(index) * -(size*2)) : (Double(index) * -(size + 4)))
                    .animation(.easeOut(duration: 0.2), value: expanded)
                    .id(accountsSorted[index].publicKey) // sorting index and view identity (publicKey) is different!
            }
        }
        .fixedSize()
    }
    
//    @ViewBuilder
//    private var leading: some View {
//        VStack(spacing: 2) {
//            ForEach(accountsSorted.indices, id:\.self) { index in
//                PFP(pubkey: accountsSorted[index].publicKey, account: accountsSorted[index], size: size)
//                    .onTapGesture {
//                        accountTapped(accountsSorted[index])
//                    }
//                    .opacity(index == 0 || expanded ? 1.0 : 0.2)
//                    .zIndex(-Double(index))
//                    .offset(y: (Double(index) * -(size - 0)))
//                    .offset(x: expanded || (index == 0) ? 0 : (Double(index) * -(size - 2)))
//                    .animation(.easeOut(duration: 0.2), value: expanded)
//                    .id(accountsSorted[index].publicKey) // sorting index and view identity (publicKey) is different!
//            }
//        }
//        .fixedSize()
//    }
//    
//    @ViewBuilder
//    private var trailing: some View {
//        VStack(spacing: 2) {
//            ForEach(accountsSorted.indices, id:\.self) { index in
//                PFP(pubkey: accountsSorted[index].publicKey, account: accountsSorted[index], size: size)
//                    .onTapGesture {
//                        accountTapped(accountsSorted[index])
//                    }
//                    .opacity(index == 0 || expanded ? 1.0 : 0.2)
//                    .zIndex(-Double(index))
//                    .offset(x: (expanded || (index == 0)) ? (Double(index) * -(size*2)) : (Double(index) * -(size + 4)))
//                    .animation(.easeOut(duration: 0.2), value: expanded)
//                    .id(accountsSorted[index].publicKey) // sorting index and view identity (publicKey) is different!
//            }
//        }
//        .fixedSize()
//    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        Color.clear
            .frame(width: size, height: size)
            .overlay(alignment: .topLeading) {
                switch fanOutDirection {
                case .leading:
                    self.bottom
                case .trailing:
                    self.bottom
                case .top:
                    self.bottom
                case .bottom:
                    self.bottom
                }
            }
            .task {
                accounts = NRState.shared.accounts
                    .filter { $0.isFullAccount }
//                    .sorted(by: {
//                        $0 == activeAccount && $1 != activeAccount
//                    })
            }
    }
    
    private func accountTapped(_ account:CloudAccount) {
        if !expanded {
            withAnimation {
                expanded = true
            }
        }
        else {
            withAnimation {
                onChange(account)
                expanded = false
            }
        }
    }
}

enum Direction {
    case leading
    case trailing
    case top
    case bottom
}

struct InlineAccountSwitcherPreviewWrap: View {
    public var fanOutDirection: Direction = .bottom
    @State var activeAccount = NRState.shared.loggedInAccount!.account
    
    var body: some View {
        InlineAccountSwitcher(activeAccount: activeAccount, onChange: { account in
            activeAccount = account
        }, size: 20.0, fanOutDirection: fanOutDirection)
    }
}

struct InlineAccountSwitcher_Previews: PreviewProvider {

    static var previews: some View {
        PreviewContainer({ pe in pe.loadAccounts() }) {
            HStack {
                VStack {
                    Text("Test")
                    InlineAccountSwitcherPreviewWrap(fanOutDirection: .top)
                    Text("End test")
                    InlineAccountSwitcherPreviewWrap(fanOutDirection: .trailing)
                }
                VStack {
                    InlineAccountSwitcherPreviewWrap(fanOutDirection: .leading)
                    Text("Test")
                    InlineAccountSwitcherPreviewWrap(fanOutDirection: .bottom)
                    Text("End test")
                }
            }
        }
    }
}
