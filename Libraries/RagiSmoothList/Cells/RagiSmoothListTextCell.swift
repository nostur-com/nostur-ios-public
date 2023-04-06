//
//  RagiSmoothListTextCell.swift
//  RagiSmoothList
//
//  Created by ragingo on 2022/12/08.
//

import SwiftUI

public struct RagiSmoothListTextCell: View {
    private let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
    }
}

struct RagiSmoothListTextCell_Previews: PreviewProvider {
    static var previews: some View {
        RagiSmoothListTextCell(text: "abc")
    }
}
