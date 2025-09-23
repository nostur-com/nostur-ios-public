//
//  SettingsDefaultZapAmount.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/07/2023.
//

import SwiftUI
import NavigationBackport

struct SettingsDefaultZapAmount: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) var dismiss
    
    @AppStorage("last_custom_zap_amount") var lastCustomZapAmount:Double = 0.0
    @State var selectedAmount:Double = SettingsStore.shared.defaultZapAmount
    @State var customAmount:Double = 0.0
    @State var showCustomAmountsheet = false
    
    var body: some View {
        VStack {
            if #available(iOS 16, *) {
                Grid {
                    GridRow {
                        ZapAmountButton(3, isSelected: selectedAmount == 3).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 3
                            dismiss()
                        }
                        ZapAmountButton(21, isSelected: selectedAmount == 21).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 21
                            dismiss()
                        }
                        ZapAmountButton(100, isSelected: selectedAmount == 100).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 100
                            dismiss()
                        }
                        ZapAmountButton(500, isSelected: selectedAmount == 500).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 500
                            dismiss()
                        }
                    }
                    GridRow {
                        ZapAmountButton(1000, isSelected: selectedAmount == 1000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 1000
                            dismiss()
                        }
                        ZapAmountButton(2000, isSelected: selectedAmount == 2000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 2000
                            dismiss()
                        }
                        ZapAmountButton(5000, isSelected: selectedAmount == 5000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 5000
                            dismiss()
                        }
                        ZapAmountButton(10000, isSelected: selectedAmount == 10000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 10000
                            dismiss()
                        }
                    }
                    GridRow {
                        ZapAmountButton(25000, isSelected: selectedAmount == 25000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 25000
                            dismiss()
                        }
                        ZapAmountButton(50000, isSelected: selectedAmount == 50000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 50000
                            dismiss()
                        }
                        ZapAmountButton(100000, isSelected: selectedAmount == 100000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 100000
                            dismiss()
                        }
                        ZapAmountButton(200000, isSelected: selectedAmount == 200000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 200000
                            dismiss()
                        }
                    }
                    GridRow {
                        ZapAmountButton(500000, isSelected: selectedAmount == 500000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 500000
                            dismiss()
                        }
                        ZapAmountButton(1000000, isSelected: selectedAmount == 1000000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 1000000
                            dismiss()
                        }
                        if lastCustomZapAmount != 0.0 {
                            ZapAmountButton(lastCustomZapAmount, isSelected: selectedAmount == lastCustomZapAmount).onTapGesture {
                                SettingsStore.shared.defaultZapAmount = lastCustomZapAmount
                                dismiss()
                            }
                        }
                        ZapAmountButton(customAmount, isSelected: selectedAmount == customAmount).onTapGesture {
                            showCustomAmountsheet = true
                        }
                        .onChange(of: customAmount) { newValue in
                            SettingsStore.shared.defaultZapAmount = newValue
                            dismiss()
                        }
                    }
                }
            }
            else {
                VStack {
                    HStack {
                        ZapAmountButton(3, isSelected: selectedAmount == 3).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 3
                            dismiss()
                        }
                        ZapAmountButton(21, isSelected: selectedAmount == 21).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 21
                            dismiss()
                        }
                        ZapAmountButton(100, isSelected: selectedAmount == 100).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 100
                            dismiss()
                        }
                        ZapAmountButton(500, isSelected: selectedAmount == 500).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 500
                            dismiss()
                        }
                    }
                    HStack {
                        ZapAmountButton(1000, isSelected: selectedAmount == 1000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 1000
                            dismiss()
                        }
                        ZapAmountButton(2000, isSelected: selectedAmount == 2000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 2000
                            dismiss()
                        }
                        ZapAmountButton(5000, isSelected: selectedAmount == 5000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 5000
                            dismiss()
                        }
                        ZapAmountButton(10000, isSelected: selectedAmount == 10000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 10000
                            dismiss()
                        }
                    }
                    HStack {
                        ZapAmountButton(25000, isSelected: selectedAmount == 25000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 25000
                            dismiss()
                        }
                        ZapAmountButton(50000, isSelected: selectedAmount == 50000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 50000
                            dismiss()
                        }
                        ZapAmountButton(100000, isSelected: selectedAmount == 100000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 100000
                            dismiss()
                        }
                        ZapAmountButton(200000, isSelected: selectedAmount == 200000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 200000
                            dismiss()
                        }
                    }
                    HStack {
                        ZapAmountButton(500000, isSelected: selectedAmount == 500000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 500000
                            dismiss()
                        }
                        ZapAmountButton(1000000, isSelected: selectedAmount == 1000000).onTapGesture {
                            SettingsStore.shared.defaultZapAmount = 1000000
                            dismiss()
                        }
                        if lastCustomZapAmount != 0.0 {
                            ZapAmountButton(lastCustomZapAmount, isSelected: selectedAmount == lastCustomZapAmount).onTapGesture {
                                SettingsStore.shared.defaultZapAmount = lastCustomZapAmount
                                dismiss()
                            }
                        }
                        ZapAmountButton(customAmount, isSelected: selectedAmount == customAmount).onTapGesture {
                            showCustomAmountsheet = true
                        }
                        .onChange(of: customAmount) { newValue in
                            SettingsStore.shared.defaultZapAmount = newValue
                            dismiss()
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .navigationTitle(String(localized:"Default zap amount"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCustomAmountsheet) {
            NBNavigationStack {
                CustomZapAmountEntry(customAmount: $customAmount)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
    }
}
