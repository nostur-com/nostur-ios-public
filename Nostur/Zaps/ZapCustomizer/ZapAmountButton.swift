//
//  ZapAmountButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/07/2023.
//

import SwiftUI

struct ZapAmountButton: View {
    let er:ExchangeRateModel = .shared
    let amount:Double
    let isSelected:Bool
    
    init(_ amount:Double, isSelected:Bool) {
        self.amount = amount
        self.isSelected = isSelected
    }
    
    var fiatPrice:String? {
        guard er.bitcoinPrice > 0 else { return nil }
        return String(format: "$%.02f",(amount / 100000000 * er.bitcoinPrice))
    }
    
    var body: some View {
        Circle()
            .strokeBorder(isSelected ? .orange : .systemBackground, lineWidth: 5)
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
                        Text(amount.satsFormatted)
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

struct ZapAmountButton_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            ZapAmountButton(1000, isSelected: false)
            ZapAmountButton(5000, isSelected: true)
        }
        .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}
