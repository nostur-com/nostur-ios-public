//
//  CustomZapAmountEntry.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/07/2023.
//

import SwiftUI

struct CustomZapAmountEntry: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var customAmount: Double
    @State private var enteredAmount = ""
    @FocusState private var focusedField: FocusedField?
    
    enum FocusedField {
        case amount
    }

    private var fiatPrice:String? {
        guard ExchangeRateModel.shared.bitcoinPrice > 0 else { return nil }
        guard let d = Double(enteredAmount), d > 0 else { return nil }
        return String(format: "$%.02f",(d / 100000000 * ExchangeRateModel.shared.bitcoinPrice))
    }
    
    private var isValidAmount:Bool {
        if let d = Double(enteredAmount), d > 0 {
            return true
        }
        return false
    }
    
    var body: some View {
        Form {
                Section(header: Text("Amount (satoshis)")) {
                    TextField("Zap custom amount", text: $enteredAmount, prompt: Text("0"))
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .amount)
                    if let d = Double(enteredAmount), d > 0, let fiatPrice = fiatPrice {
                        Text(fiatPrice)
                            .foregroundColor(.secondary)
                    }
                }
        }
        .formStyleGrouped()
        .onAppear {
            customAmount = 0
            focusedField = .amount
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button("Done", systemImage: "checkmark") {
                    if let d = Double(enteredAmount), d > 0 {
                        customAmount = Double(d)
                        dismiss()
                    }
                }
                .buttonStyleGlassProminent()
                .disabled(!isValidAmount)
            }
        }
    }
}

import NavigationBackport

#Preview("CustomZapAmountEntry") {
    NBNavigationStack {
        CustomZapAmountEntry(customAmount: .constant(400.0))
    }
}
