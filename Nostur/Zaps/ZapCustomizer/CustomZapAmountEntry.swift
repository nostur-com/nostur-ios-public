//
//  CustomZapAmountEntry.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/07/2023.
//

import SwiftUI

struct CustomZapAmountEntry: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var customAmount:Double
    @State private var enteredAmount = ""
    @FocusState private var focusedField: FocusedField?
    enum FocusedField {
        case amount
    }
    
    let er:ExchangeRateModel = .shared
    
    var fiatPrice:String? {
        guard er.bitcoinPrice > 0 else { return nil }
        guard let d = Double(enteredAmount), d > 0 else { return nil }
        return String(format: "$%.02f",(d / 100000000 * er.bitcoinPrice))
    }
    
    var isValidAmount:Bool {
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
        .formStyle(.grouped)
        .onAppear {
            customAmount = 0
            focusedField = .amount
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    if let d = Double(enteredAmount), d > 0 {
                        customAmount = Double(d)
                        dismiss()
                    }
                }
                .disabled(!isValidAmount)
            }
        }
    }
}

struct CustomZapAmountEntry_Previews: PreviewProvider {
    @State static var customAmount:Double = 400.0
    static var previews: some View {
        HStack {
            CustomZapAmountEntry(customAmount: $customAmount)
        }
        .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}
