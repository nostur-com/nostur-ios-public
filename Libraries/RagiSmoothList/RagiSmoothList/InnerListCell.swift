////
////  InnerListCell.swift
////  RagiSmoothList
////
////  Created by ragingo on 2022/12/08.
////
//
//import SwiftUI
//import UIKit
//
//final class InnerListCell<Content: View>: UICollectionViewCell {
//    private var hostingView = HostingView<Content>()
//
////    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
////        let targetSize = CGSize(width: layoutAttributes.frame.width, height: 0)
////        layoutAttributes.frame.size = contentView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
////        return layoutAttributes
////    }
//
//    func configure(content: Content) {
//        hostingView.configure(content: content)
//        hostingView.backgroundColor = UIColor(named: "ListBackground")
//        hostingView.invalidateIntrinsicContentSize()
//
//        if !subviews.contains(hostingView) {
//            contentView.addSubview(hostingView)
//            hostingView.translatesAutoresizingMaskIntoConstraints = false
//            NSLayoutConstraint.activate([
//                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
//                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
//                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
//                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
//            ])
//        }
//    }
//}
//
//
//class FullWidthCollectionViewCell: UICollectionViewCell {
//    override func systemLayoutSizeFitting(
//        _ targetSize: CGSize,
//        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
//        verticalFittingPriority: UILayoutPriority) -> CGSize {
//        
//        // Replace the height in the target size to
//        // allow the cell to flexibly compute its height
////        var targetSize = targetSize
////        targetSize.height = CGFloat.greatestFiniteMagnitude
//        
//        // The .required horizontal fitting priority means
//        // the desired cell width (targetSize.width) will be
//        // preserved. However, the vertical fitting priority is
//        // .fittingSizeLevel meaning the cell will find the
//        // height that best fits the content
//            let size = super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .defaultHigh)
//        
//        return size
//    }
//}
