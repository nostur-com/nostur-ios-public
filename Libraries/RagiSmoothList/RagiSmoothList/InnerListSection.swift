//
//  InnerListSection.swift
//  RagiSmoothList
//
//  Created by ragingo on 2022/12/09.
//

import SwiftUI
import UIKit

final class InnerListSection<Content: View>: UICollectionReusableView {
    private var hostingView = HostingView<Content>()

    func configure(content: Content) {
        hostingView.configure(content: content)
        hostingView.invalidateIntrinsicContentSize()

        if !subviews.contains(hostingView) {
            addSubview(hostingView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
}
