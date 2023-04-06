//
//  InnerListCell.swift
//  RagiSmoothList
//
//  Created by ragingo on 2022/12/08.
//

import SwiftUI
import UIKit

final class InnerListCell<Content: View>: UICollectionViewCell {
    private var hostingView = HostingView<Content>()

    func configure(content: Content) {
        hostingView.configure(content: content)
        hostingView.invalidateIntrinsicContentSize()

        if !subviews.contains(hostingView) {
            contentView.addSubview(hostingView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }
}
