////
////  CollectionView.swift
////  RagiSmoothList
////
////  Created by ragingo on 2022/12/17.
////
//
//import SwiftUI
//import UIKit
//
//extension UICollectionView {
//    var widestCellWidth: CGFloat {
//        let insets = contentInset.left + contentInset.right
//        return bounds.width - insets
//    }
//}
//
//final class CollectionViewHolder<
//    SectionType: Hashable,
//    ItemType: Hashable,
//    SectionHeader: View,
//    SectionFooter: View,
//    Cell: View
//> {
//    // swiftlint:disable:next line_length
//    typealias SupplementaryViewProvider = UICollectionViewDiffableDataSource<SectionType, ItemType>.SupplementaryViewProvider
//    typealias SwipeActionProvider = UICollectionLayoutListConfiguration.SwipeActionsConfigurationProvider
//    typealias DataSourceType = DataSource<SectionType, ItemType>
//
//    private(set) lazy var dataSource: DataSourceType = createDataSource()
//    private let sectionHeaderContent: (SectionType, [ItemType]) -> SectionHeader
//    private let sectionFooterContent: (SectionType, [ItemType]) -> SectionFooter
//    private let cellContent: (ItemType) -> Cell
//    private let onLoadMore: () -> Void
//    private let onRefresh: () -> Void
//
//    private let collectionView: CustomCollectionView<Cell, SectionHeader, SectionFooter>
//    private var layoutListConfiguration = UICollectionLayoutListConfiguration(appearance: .plain)
//
//    init(
//        @ViewBuilder sectionHeaderContent: @escaping (SectionType, [ItemType]) -> SectionHeader,
//        @ViewBuilder sectionFooterContent: @escaping (SectionType, [ItemType]) -> SectionFooter,
//        @ViewBuilder cellContent: @escaping (ItemType) -> Cell,
//        onLoadMore: @escaping () -> Void,
//        onRefresh: @escaping () -> Void,
//        delegate: UICollectionViewDelegate,
//        onInitialized: @escaping (UICollectionView) -> Void
//    ) {
//        self.sectionHeaderContent = sectionHeaderContent
//        self.sectionFooterContent = sectionFooterContent
//        self.cellContent = cellContent
//        self.onLoadMore = onLoadMore
//        self.onRefresh = onRefresh
//
//        collectionView = .init(onRefresh: onRefresh)
//        collectionView.delegate = delegate
//
////        let layout = collectionView.collectionViewLayout
////            if let flowLayout = layout as? UICollectionViewFlowLayout {
////                flowLayout.estimatedItemSize = CGSize(
////                    width: collectionView.widestCellWidth,
////                    // Make the height a reasonable estimate to
////                    // ensure the scroll bar remains smooth
////                    height: 250
////                )
////            }
//        let layout = collectionView.collectionViewLayout
//        if let flowLayout = layout as? UICollectionViewFlowLayout {
//            flowLayout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
//        }
//        
//        self.dataSource.supplementaryViewProvider = supplementaryViewProvider()
//
//        onInitialized(collectionView)
//    }
//
//    func updateLayout(listStyle: any RagiSmoothListStyle, listConfiguration: RagiSmoothListConfiguration?) {
//        let oldConfig = self.layoutListConfiguration
//
//        self.layoutListConfiguration = .init(appearance: decideAppearance(listStyle: listStyle))
//        self.configureStyles(listConfiguration: listConfiguration, layoutListConfiguration: &layoutListConfiguration)
//        self.layoutListConfiguration.leadingSwipeActionsConfigurationProvider =
//            oldConfig.leadingSwipeActionsConfigurationProvider
//        self.layoutListConfiguration.trailingSwipeActionsConfigurationProvider =
//            oldConfig.trailingSwipeActionsConfigurationProvider
//
//        collectionView.updateLayout(layoutListConfiguration)
//    }
//
//    func swipeActions(
//        edge: SwipeStartEdge,
//        allowFullSwipe: Bool = true,
//        actions: @escaping (IndexPath, SectionType, ItemType) -> [UIContextualAction]
//    ) {
//        let provider: SwipeActionProvider = { [weak self] indexPath -> UISwipeActionsConfiguration? in
//            guard let self else { return nil }
//            let snapshot = self.dataSource.snapshot()
//            let section = snapshot.sectionIdentifiers[indexPath.section]
//            let item = snapshot.itemIdentifiers(inSection: section)[indexPath.row]
//            return UISwipeActionsConfiguration(actions: actions(indexPath, section, item))
//        }
//
//        switch edge {
//        case .leading:
//            layoutListConfiguration.leadingSwipeActionsConfigurationProvider = provider
//
//        case .trailing:
//            layoutListConfiguration.trailingSwipeActionsConfigurationProvider = provider
//        }
//
//        collectionView.updateLayout(layoutListConfiguration)
//    }
//
//    func scrollToTop(animated: Bool = true) {
//        collectionView.scrollToTop(animated: animated)
//    }
//    
//    func scrollToIndex(_ index:Int, animated: Bool = true, autoScroll:Bool = false) {
//        guard index == 0 || dataSource.itemIdentifier(for: IndexPath(item: index, section: 0)) != nil else { return }
//        collectionView.scrollToItem(index, animated: animated, autoScroll: autoScroll)
//    }
//
//    private func configureStyles(
//        listConfiguration: RagiSmoothListConfiguration?,
//        layoutListConfiguration: inout UICollectionLayoutListConfiguration
//    ) {
//        layoutListConfiguration.headerMode = SectionHeader.self is EmptyView.Type ? .none : .supplementary
//        layoutListConfiguration.footerMode = SectionFooter.self is EmptyView.Type ? .none : .supplementary
//
//        if #available(iOS 15.0, *) {
//            layoutListConfiguration.headerTopPadding = 0
//        }
//
//        guard let listConfiguration else { return }
//
//        layoutListConfiguration.showsSeparators = listConfiguration.separator.isVisible
//
//        if let separatorColor = listConfiguration.separator.color {
//            if #available(iOS 14.5, *) {
//                layoutListConfiguration.separatorConfiguration.color = UIColor(separatorColor)
//            }
//        }
//
//        if let separatorInsets = listConfiguration.separator.insets {
//            if #available(iOS 14.5, *) {
//                let insets = NSDirectionalEdgeInsets(
//                    top: separatorInsets.top,
//                    leading: separatorInsets.leading,
//                    bottom: separatorInsets.bottom,
//                    trailing: separatorInsets.trailing
//                )
//                layoutListConfiguration.separatorConfiguration.topSeparatorInsets = insets
//                layoutListConfiguration.separatorConfiguration.bottomSeparatorInsets = insets
//            }
//        }
//    }
//
//    private func decideAppearance(listStyle: any RagiSmoothListStyle) -> UICollectionLayoutListConfiguration.Appearance {
//        let appearance: UICollectionLayoutListConfiguration.Appearance
//        switch listStyle {
//        case is PlainListStyle:
//            appearance = .plain
//        case is GroupedListStyle:
//            appearance = .grouped
//        case is InsetListStyle:
//            appearance = .insetGrouped // MEMO: UICollectionView に .inset は存在しない
//        case is InsetGroupedListStyle:
//            appearance = .insetGrouped
//        case is SidebarListStyle:
//            appearance = .sidebar
//        case is DefaultListStyle:
//            appearance = .plain
//        default:
//            appearance = .plain
//        }
//        return appearance
//    }
//
//    private func createDataSource() -> DataSourceType {
//        DataSource(
//            collectionView: collectionView,
//            cellProvider: { [weak self] collectionView, indexPath, item -> UICollectionViewCell? in
//                guard let self else { return nil }
//
//                guard let cell = self.collectionView.dequeueCell(for: indexPath) else {
//                    return nil
//                }
//
//                if self.collectionView.isLastItem(indexPath) {
//                    self.onLoadMore()
//                }
//
//                let content = self.cellContent(item)
//                cell.configure(content: content)
//                return cell
//            }
//        )
//    }
//}
//
//// MARK: - Section Header/Footer
//private extension CollectionViewHolder {
//    func supplementaryViewProvider() -> SupplementaryViewProvider? {
//        let provider: SupplementaryViewProvider = { [weak self] _, elementKind, indexPath in
//            guard let self else { return nil }
//
//            switch elementKind {
//            case UICollectionView.elementKindSectionHeader:
//                return self.makeSectionHeader(indexPath: indexPath)
//            case UICollectionView.elementKindSectionFooter:
//                return self.makeSectionFooter(indexPath: indexPath)
//            default:
//                return nil
//            }
//        }
//        return provider
//    }
//
//    func makeSectionHeader(indexPath: IndexPath) -> UICollectionReusableView? {
//        guard let view = collectionView.dequeueSectionHeader(for: indexPath) else {
//            return nil
//        }
//
//        let snapshot = dataSource.snapshot()
//        let sectionData = snapshot.sectionIdentifiers[indexPath.section]
//        let itemsData = snapshot.itemIdentifiers(inSection: sectionData)
//        let content = sectionHeaderContent(sectionData, itemsData)
//        view.configure(content: content)
//
//        return view
//    }
//
//    func makeSectionFooter(indexPath: IndexPath) -> UICollectionReusableView? {
//        guard let view = collectionView.dequeueSectionFooter(for: indexPath) else {
//            return nil
//        }
//
//        let snapshot = dataSource.snapshot()
//        let sectionData = snapshot.sectionIdentifiers[indexPath.section]
//        let itemsData = snapshot.itemIdentifiers(inSection: sectionData)
//        let content = sectionFooterContent(sectionData, itemsData)
//        view.configure(content: content)
//
//        return view
//    }
//}
