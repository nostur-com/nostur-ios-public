//
//  ZapAmountButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/07/2023.
//

import SwiftUI

struct ZapAmountButton: View {
    @Environment(\.theme) private var theme
    private let amount:Double
    private let isSelected:Bool
    
    init(_ amount:Double, isSelected:Bool) {
        self.amount = amount
        self.isSelected = isSelected
    }
    
    private var fiatPrice:String? {
        guard ExchangeRateModel.shared.bitcoinPrice > 0 else { return nil }
        return String(format: "$%.02f",(amount / 100000000 * ExchangeRateModel.shared.bitcoinPrice))
    }
    
    var body: some View {
        Circle()
            .strokeBorder(isSelected ? .orange : theme.background, lineWidth: 5)
            .background(Circle().fill(.orange))
            .frame(width: 75, height: 75)
            .overlay(alignment: .center) {
                VStack {
                    if amount == 0.0 {
                        Text("Custom")
                            .font(.caption)
                            .foregroundColor(Color.white)
                            .fontWeight(.bold)
                    }
                    else {
                        Text(amount, format: .number.notation((.compactName)))
                            .foregroundColor(Color.white)
                            .fontWeight(.bold)
                        if let fiatPrice {
                            Text(fiatPrice)
                                .font(.caption)
                                .foregroundColor(Color.white.opacity(0.75))
                        }
                    }
                }
                .frame(width: 65, height: 65)
            }
            .opacity(isSelected ? 1.0 : 0.75 )
    }
}

#Preview("ZapAmountButton") {
    HStack {
        ZapAmountButton(1000, isSelected: false)
        ZapAmountButton(5000, isSelected: true)
    }
}
