//
//  ZapCustomizerSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/07/2023.
//

import SwiftUI
import NavigationBackport

struct ZapCustomizerSheet: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var ss:SettingsStore = .shared
    public var name:String
    public var customZapId:UUID?
    public var supportsZap = false
    public var sendAction:((CustomZap) -> Void)?
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("last_custom_zap_amount") private var lastCustomZapAmount:Double = 0.0
    @State private var zapMessage = ""
    @State private var selectedAmount:Double = 3
    @State private var customAmount:Double = 0.0
    @State private var showCustomAmountsheet = false
    @State private var setAmountAsDefault = false
    
    var body: some View {
        NBNavigationStack {
            VStack(spacing: 10) {
                if ss.nwcShowBalance && ss.nwcReady {
                    HStack {
                        Text("Your balance:")
                        NWCWalletBalance(noIcon: true)
                    }
                }
                Grid {
                    GridRow {
                        ZapAmountButton(3, isSelected: selectedAmount == 3).onTapGesture {
                            selectedAmount = 3
                        }
                        ZapAmountButton(21, isSelected: selectedAmount == 21).onTapGesture {
                            selectedAmount = 21
                        }
                        ZapAmountButton(100, isSelected: selectedAmount == 100).onTapGesture {
                            selectedAmount = 100
                        }
                        ZapAmountButton(500, isSelected: selectedAmount == 500).onTapGesture {
                            selectedAmount = 500
                        }
                    }
                    GridRow {
                        ZapAmountButton(1000, isSelected: selectedAmount == 1000).onTapGesture {
                            selectedAmount = 1000
                        }
                        ZapAmountButton(2000, isSelected: selectedAmount == 2000).onTapGesture {
                            selectedAmount = 2000
                        }
                        ZapAmountButton(5000, isSelected: selectedAmount == 5000).onTapGesture {
                            selectedAmount = 5000
                        }
                        ZapAmountButton(10000, isSelected: selectedAmount == 10000).onTapGesture {
                            selectedAmount = 10000
                        }
                    }
                    GridRow {
                        ZapAmountButton(25000, isSelected: selectedAmount == 25000).onTapGesture {
                            selectedAmount = 25000
                        }
                        ZapAmountButton(50000, isSelected: selectedAmount == 50000).onTapGesture {
                            selectedAmount = 50000
                        }
                        ZapAmountButton(100000, isSelected: selectedAmount == 100000).onTapGesture {
                            selectedAmount = 100000
                        }
                        ZapAmountButton(200000, isSelected: selectedAmount == 200000).onTapGesture {
                            selectedAmount = 200000
                        }
                    }
                    GridRow {
                        ZapAmountButton(500000, isSelected: selectedAmount == 500000).onTapGesture {
                            selectedAmount = 500000
                        }
                        ZapAmountButton(1000000, isSelected: selectedAmount == 1000000).onTapGesture {
                            selectedAmount = 1000000
                        }
                        if lastCustomZapAmount != 0.0 {
                            ZapAmountButton(lastCustomZapAmount, isSelected: selectedAmount == lastCustomZapAmount).onTapGesture {
                                selectedAmount = lastCustomZapAmount
                            }
                        }
                        ZapAmountButton(customAmount, isSelected: selectedAmount == customAmount).onTapGesture {
                            showCustomAmountsheet = true
                        }
                        .onChange(of: customAmount) { newValue in
                            selectedAmount = newValue
                            lastCustomZapAmount = selectedAmount
                        }
                    }
                }
                
                if supportsZap, let account = account() {
                    HStack(alignment: .center) {
                        PFP(pubkey: account.publicKey, account: account)
                        TextField("Add public note (optional)", text: $zapMessage)
                            .multilineTextAlignment(.leading)
                            .lineLimit(5, reservesSpace: true)
                            .textFieldStyle(.roundedBorder)
                            .border(themes.theme.lineColor.opacity(0.5))
                    }
                    .padding(10)
                }
                
                Button {
                    if sendAction != nil {
                        sendAction?(CustomZap(
                            publicNote: zapMessage,
                            customZapId: customZapId,
                            amount: selectedAmount
                        ))
                    }
                    else {
                        sendNotification(.sendCustomZap,
                                         CustomZap(
                                            publicNote: zapMessage,
                                            customZapId: customZapId,
                                            amount: selectedAmount
                                         ))
                    }
                    if setAmountAsDefault {
                        SettingsStore.shared.defaultZapAmount = selectedAmount
                    }
                    dismiss()
                } label: {
                    Text("Send \(selectedAmount.clean) sats to \(name)")
                        .lineLimit(2)
                        .foregroundColor(Color.white)
                        .fontWeight(.bold)
                        .padding(10)
                        .background(themes.theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8.0))
                        .frame(maxWidth: 300)
                        .controlSize(.large)
                }
                
                Toggle(isOn: $setAmountAsDefault) {
                    Text("Remember this amount for all zaps", comment:"Toggle on zap screen to set selected amount as default for all zaps")
                }
                .padding(.horizontal, 20)
                Spacer()
            }
            .navigationTitle(String(localized:"Send sats", comment:"Title of sheet showing zap options when sending sats (satoshis)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel")
                    }
                    
                }
            }
            .sheet(isPresented: $showCustomAmountsheet) {
                NBNavigationStack {
                    CustomZapAmountEntry(customAmount: $customAmount)
                }
                .presentationBackground(themes.theme.background)
            }
            .onAppear {
                selectedAmount = SettingsStore.shared.defaultZapAmount
            }
        }
    }
}

struct ZapCustomizerSheetInfo: Identifiable {
    let name:String
    var customZapId:UUID?
    var id:UUID { customZapId ?? UUID() }
}

struct CustomZap: Identifiable {
    var id:UUID { customZapId ?? UUID() }
    var publicNote = ""
    var customZapId:UUID?
    let amount:Double
}

#Preview("ZapCustomizerSheet") {
    PreviewContainer({ pe in pe.loadPosts() }) {
        if let nrPost = PreviewFetcher.fetchNRPost() {
            ZapCustomizerSheet(name:nrPost.anyName, customZapId: UUID(), supportsZap: true)
                .environmentObject(Themes.default)
        }
    }
}
