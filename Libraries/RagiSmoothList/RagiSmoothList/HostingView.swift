//
//  HostingView.swift
//  RagiSmoothList
//
//  Created by ragingo on 2022/12/09.
//

import SwiftUI
import UIKit

final class HostingView<Content: View>: UIView {
    private let hostingController = UIHostingController<Content?>(rootView: nil)

    override init(frame: CGRect) {
        super.init(frame: frame)
        hostingController.view.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(content: Content) {
        hostingController.rootView = content
        hostingController.view.invalidateIntrinsicContentSize()

        if !subviews.contains(hostingController.view) {
            addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
}
