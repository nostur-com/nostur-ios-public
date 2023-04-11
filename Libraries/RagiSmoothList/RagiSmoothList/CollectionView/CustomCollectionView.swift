////
////  CustomCollectionView.swift
////  RagiSmoothList
////
////  Created by ragingo on 2022/12/22.
////
//
//import SwiftUI
//import UIKit
//
//struct LayoutMetrics {
//    static let horizontalMargin = 16.0
//    static let sectionSpacing = 10.0
//    static let cornerRadius = 10.0
//}
//
//final class CustomCollectionView<
//    Cell: View,
//    SectionHeader: View,
//    SectionFooter: View
//>: UICollectionView, UICollectionViewDelegateFlowLayout {
//    
////    typealias DataSourceType = DataSource<SectionType, ItemType>
//    
//    private let cellID = UUID().uuidString
//    private let sectionHeaderID = UUID().uuidString
//    private let sectionFooterID = UUID().uuidString
//
//    private let onRefresh: () -> Void
//
//    init(onRefresh: @escaping () -> Void) {
//        self.onRefresh = onRefresh
//        super.init(frame: .zero, collectionViewLayout: .init())
////        self.maximumContentSizeCategory = .extraExtraExtraLarge
//        keyboardDismissMode = .onDragWithAccessory
//
//        // refresh control
////        refreshControl = UIRefreshControl()
////        refreshControl?.addTarget(self, action: #selector(onRefreshControlValueChanged(sender:)), for: .valueChanged)
//
//        // cell, section header, section footer
//        register(InnerListCell<Cell>.self, forCellWithReuseIdentifier: cellID)
//        register(
//            InnerListSection<SectionHeader>.self,
//            forSupplementaryViewOfKind: Self.elementKindSectionHeader,
//            withReuseIdentifier: sectionHeaderID
//        )
//        register(
//            InnerListSection<SectionFooter>.self,
//            forSupplementaryViewOfKind: Self.elementKindSectionFooter,
//            withReuseIdentifier: sectionFooterID
//        )
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//    
////    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
////        // dont know how to use this... somehow need to estimate the height of vPosts.
////    }
//
//    func dequeueCell(for indexPath: IndexPath) -> InnerListCell<Cell>? {
//        dequeueReusableCell(
//            withReuseIdentifier: cellID,
//            for: indexPath
//        ) as? InnerListCell<Cell>
//    }
//
//    func dequeueSectionHeader(for indexPath: IndexPath) -> InnerListSection<SectionHeader>? {
//        dequeueReusableSupplementaryView(
//            ofKind: Self.elementKindSectionHeader,
//            withReuseIdentifier: sectionHeaderID,
//            for: indexPath
//        ) as? InnerListSection<SectionHeader>
//    }
//
//    func dequeueSectionFooter(for indexPath: IndexPath) -> InnerListSection<SectionFooter>? {
//        dequeueReusableSupplementaryView(
//            ofKind: Self.elementKindSectionFooter,
//            withReuseIdentifier: sectionFooterID,
//            for: indexPath
//        ) as? InnerListSection<SectionFooter>
//    }
//
//    func isLastItem(_ indexPath: IndexPath) -> Bool {
//        let isLastSection = numberOfSections == indexPath.section + 1
//        let isLastItem = numberOfItems(inSection: indexPath.section) == indexPath.row + 1
//        return isLastSection && isLastItem
//    }
//
//    func scrollToTop(animated: Bool = true) {
//        setContentOffset(.zero, animated: animated)
//    }
//    
//    func scrollToItem(_ index:Int, animated: Bool = true, autoScroll:Bool = false) {
////        reloadData()
//        if (index == 0) {
//            if autoScroll {
//                setContentOffset(.zero, animated: animated)
//            }
//            else {
//                setContentOffset(CGPoint(x: 0, y: NOSTUR_AUTOSCROLL_OFFSET), animated: animated)
//            }
//        }
//        else {
//            scrollToItem(at: IndexPath(item: index, section: 0), at: .top, animated: animated)
//        }
//    }
//    
//
//    
////    // Returns a compositional layout section for cells in a list.
////    private func createListSection(_ layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
////        let config = UICollectionLayoutListConfiguration(appearance: .plain)
////        let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
////        section.contentInsets = .zero
////        section.contentInsets.leading = LayoutMetrics.horizontalMargin
////        section.contentInsets.trailing = LayoutMetrics.horizontalMargin
////        section.contentInsets.bottom = LayoutMetrics.sectionSpacing
////        return section
////    }
//
//    func updateLayout(_ configuration: UICollectionLayoutListConfiguration) {
//        
//        let layout = UICollectionViewCompositionalLayout { [unowned self] _, layoutEnvironment in
//            
//            let config = UICollectionLayoutListConfiguration(appearance: .plain)
//            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
//            section.contentInsets = .zero
//            return section
////
////            return createListSection(layoutEnvironment)
//            
//        }
//        collectionViewLayout = layout
//        
////        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
////
//////            let config = UICollectionLayoutListConfiguration(appearance: .plain)
//////            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
//////            section.contentInsets = .zero
//////            return section
//////
////            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
////
////        }
////
////        collectionViewLayout = layout
////        
////        collectionViewLayout.invalidateLayout()
////        self.layoutIfNeeded()
////        self.setNeedsLayout()
////        self.layoutIfNeeded()
////        collectionViewLayout.invalidateLayout()
//    }
//
//    @objc
//    private func onRefreshControlValueChanged(sender: UIRefreshControl) {
//        onRefresh()
//        sender.endRefreshing()
//    }
//}
