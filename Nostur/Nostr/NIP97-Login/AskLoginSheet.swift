//
//  AskLoginSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/03/2024.
//

import SwiftUI

struct AskLoginSheet: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var themes: Themes
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var vm: Nip97LoginModel
    
    private var askLoginInfo: AskLoginInfo
    
    init(askLoginInfo: AskLoginInfo, account: CloudAccount) {
        self.askLoginInfo = askLoginInfo
        _vm = StateObject(wrappedValue: Nip97LoginModel(askLoginInfo: askLoginInfo, account: account))
    }
    
    private var accounts: [CloudAccount] {
        AccountsState.shared.accounts
            .sorted(by: { $0.publicKey < $1.publicKey })
            .filter { $0.isFullAccount }
    }
    
    var body: some View {
        VStack {
            Spacer()
            switch vm.state {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.green)
                    .frame(height: 75)
                if let redirectUrl = vm.redirectUrl {
                    Button("Continue") {
                        guard let url = URL(string: redirectUrl) else { return }
                        openURL(url)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .error:
                Text("**Login error**")
            case .timeout:
                Text("**Login timeout**")
            default:
                Text("Approve login on \(vm.askLoginInfo.domain)?")
                if accounts.count > 1 {
                    Text("Choose account")
                        .font(.caption)
                        .foregroundColor(.gray)
                    HStack {
                        ForEach(accounts) { account in
                            PFP(pubkey: account.publicKey, account: account, size: 30)
                                .onTapGesture {
                                    vm.account = account
                                }
                                .opacity(vm.account == account ? 1.0 : 0.25)
                                .padding(5)
                                .background(vm.account == account ? themes.theme.accent : Color.clear)
                                .clipShape(Circle())
                                .overlay(alignment: .bottom) {
                                    if vm.account == account {
                                        Text(account.anyName)
                                            .font(.system(size: 10))
                                            .lineLimit(1)
                                            .fixedSize()
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(themes.theme.accent)
                                            .cornerRadius(13)
                                            .offset(y: 10)
                                    }
                                }
                        }
                    }
                    .padding(.bottom, 15)
                }
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: vm.login) {
                        switch vm.state {
                        case .loggingIn:
                            ProgressView()
                        default:
                            Text("Approve")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Spacer()
        }
        .navigationTitle("Login request")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: self.askLoginInfo) { askLoginInfo in
            vm.newLoginInfo(askLoginInfo)
        }
    }
}

struct AskLoginInfo: Identifiable, Equatable {
    let id = UUID()
    let domain: String
    let challenge: String
}

//#Preview {
//    AskLoginSheet()
//}
