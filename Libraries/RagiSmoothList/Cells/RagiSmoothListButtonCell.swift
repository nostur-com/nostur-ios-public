//
//  RagiSmoothListButtonCell.swift
//  RagiSmoothList
//
//  Created by ragingo on 2022/12/08.
//

import SwiftUI

public struct RagiSmoothListButtonCell<Label: View>: View {
    private let label: () -> Label
    private let action: () -> Void

    public init(
        @ViewBuilder label: @escaping () -> Label,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action, label: label)
    }
}

struct RagiSmoothListButtonCell_Previews: PreviewProvider {
    static var previews: some View {
        RagiSmoothListButtonCell(
            label: {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("warning!")
            },
            action: {}
        )
    }
}
