//
//  InnerList.swift
//  RagiSmoothList
//
//  Created by ragingo on 2022/12/08.
//

import SwiftUI
import UIKit

struct InnerList<
    SectionType: Identifiable & Hashable,
    ItemType: Identifiable & Hashable,
    SectionHeader: View,
    SectionFooter: View,
    Cell: View
>: UIViewControllerRepresentable {
    typealias ListSectionModelType = RagiSmoothListSectionModel<SectionType, ItemType>
    typealias ListDataType = [ListSectionModelType]
    typealias UIViewControllerType = UIViewController
    typealias RowDeletedCallback = ((sectionIndex: Int, itemIndex: Int, section: SectionType, item: ItemType)) -> Void
    typealias RowAppearedCallback = ((sectionIndex: Int, itemIndex: Int, item: ItemType)) -> Void
    typealias FinishedScrollingCallback = (Bool) -> Void
    typealias CollectionViewHolderType = CollectionViewHolder<SectionType, ItemType, SectionHeader, SectionFooter, Cell>

    @Binding private var data: ListDataType
    private let listStyle: any RagiSmoothListStyle
    @Binding private var listConfiguration: RagiSmoothListConfiguration
    private let sectionHeaderContent: (SectionType, [ItemType]) -> SectionHeader
    private let sectionFooterContent: (SectionType, [ItemType]) -> SectionFooter
    private let cellContent: (ItemType) -> Cell
    @Binding private var needsRefresh: Bool
    @Binding private var needsScrollToTop: Bool
    @Binding private var needsScrollToIndex: Int?
    private let onLoadMore: () -> Void
    private let onRefresh: () -> Void
    private let onRowDeleted: RowDeletedCallback
    private let onRowAppeared: RowAppearedCallback
    private let onFinishedScrolling: FinishedScrollingCallback
    private var searchable: (bindableText: Binding<String>?, placeholder: String)?

    init(
        data: Binding<ListDataType>,
        listStyle: any RagiSmoothListStyle,
        listConfiguration: Binding<RagiSmoothListConfiguration>,
        @ViewBuilder sectionHeaderContent: @escaping (SectionType, [ItemType]) -> SectionHeader,
        @ViewBuilder sectionFooterContent: @escaping (SectionType, [ItemType]) -> SectionFooter,
        @ViewBuilder cellContent: @escaping (ItemType) -> Cell,
        needsRefresh: Binding<Bool>,
        onLoadMore: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onRowDeleted: @escaping RowDeletedCallback,
        onRowAppeared: @escaping RowAppearedCallback,
        onFinishedScrolling: @escaping FinishedScrollingCallback,
        searchable: (bindableText: Binding<String>?, placeholder: String)?,
        needsScrollToTop: Binding<Bool>,
        needsScrollToIndex: Binding<Int?>
    ) {
        self._data = data
        self.listStyle = listStyle
        self._listConfiguration = listConfiguration
        self.sectionHeaderContent = sectionHeaderContent
        self.sectionFooterContent = sectionFooterContent
        self.cellContent = cellContent
        self._needsRefresh = needsRefresh
        self.onLoadMore = onLoadMore
        self.onRefresh = onRefresh
        self.onRowDeleted = onRowDeleted
        self.onRowAppeared = onRowAppeared
        self.onFinishedScrolling = onFinishedScrolling
        self.searchable = searchable
        self._needsScrollToTop = needsScrollToTop
        self._needsScrollToIndex = needsScrollToIndex
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        let viewController = UIViewControllerType()

        let searchBar = makeSearchBar(parent: viewController)
        context.coordinator.searchBar = searchBar
        searchBar.delegate = context.coordinator

        let collectionViewHolder = makeCollectionViewHolder(parent: viewController, searchBar: searchBar, coordinator:context.coordinator)
        context.coordinator.collectionViewHolder = collectionViewHolder
        
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        if needsRefresh, let collectionViewHolder = context.coordinator.collectionViewHolder {
            refreshData(collectionViewHolder)
            Task {
                needsRefresh = false
            }
        }

        if needsScrollToTop, let collectionViewHolder = context.coordinator.collectionViewHolder {
            collectionViewHolder.scrollToTop()
            Task {
                needsScrollToTop = false
            }
        }
        
        if let index = needsScrollToIndex, let collectionViewHolder = context.coordinator.collectionViewHolder {
            if let _ = data[safe: 0]?.items[safe: index] {
                collectionViewHolder.scrollToIndex(index, animated: false)
            }
            Task {
                needsScrollToIndex = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UISearchBarDelegate, UICollectionViewDelegate, UIScrollViewDelegate {
        private let parent: InnerList
        fileprivate var collectionViewHolder: CollectionViewHolderType?
        fileprivate var searchBar: UISearchBar?

        init(parent: InnerList) {
            self.parent = parent
        }
        
        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            if let item = parent.data[safe: 0]?.items[safe: indexPath.row] {
                parent.onRowAppeared((sectionIndex: indexPath.section, itemIndex: indexPath.row,  item: item))
            }
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if scrollView.contentOffset.y < 250 {
                parent.onFinishedScrolling(true)
            }
            else {
                parent.onFinishedScrolling(false)
            }
        }

        // MARK: - UISearchBarDelegate
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.searchable?.bindableText?.wrappedValue = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.endEditing(true)
        }
    }

    private func makeSearchBar(parent viewController: UIViewControllerType) -> UISearchBar {
        let searchBar = UISearchBar()
        viewController.view.addSubview(searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.autocapitalizationType = .none
        searchBar.placeholder = searchable?.placeholder
        searchBar.heightAnchor.constraint(equalToConstant: 0).isActive = searchable == nil
        return searchBar
    }

    private func makeCollectionViewHolder(
        parent viewController: UIViewControllerType,
        searchBar: UISearchBar,
        coordinator: Coordinator
    ) -> CollectionViewHolderType {
        let collectionViewHolder = CollectionViewHolder(
            sectionHeaderContent: sectionHeaderContent,
            sectionFooterContent: sectionFooterContent,
            cellContent: cellContent,
            onLoadMore: onLoadMore,
            onRefresh: onRefresh,
            delegate: coordinator
        ) { uiCollectionView in
            uiCollectionView.translatesAutoresizingMaskIntoConstraints = false
            uiCollectionView.backgroundColor = UIColor(named: "ListBackground")
            viewController.view.addSubview(uiCollectionView)

            NSLayoutConstraint.activate([
                // searchBar
                viewController.view.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor),
                viewController.view.topAnchor.constraint(equalTo: searchBar.topAnchor),
                // collection view
                viewController.view.leadingAnchor.constraint(equalTo: uiCollectionView.leadingAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: uiCollectionView.trailingAnchor),
                searchBar.bottomAnchor.constraint(equalTo: uiCollectionView.topAnchor),
                viewController.view.bottomAnchor.constraint(equalTo: uiCollectionView.bottomAnchor)
            ])
        }

        collectionViewHolder.updateLayout(listStyle: listStyle, listConfiguration: listConfiguration)
        collectionViewHolder.swipeActions(edge: .trailing) { indexPath, section, item in
            var actions: [UIContextualAction] = []

            if let editableCell = item as? RagiSmoothListCellEditable, editableCell.canEdit {
                actions += [makeDeleteAction(indexPath: indexPath, section: section, item: item)]
            }

            return actions
        }

        return collectionViewHolder
    }

    private func refreshData(_ collectionViewHolder: CollectionViewHolderType) {
        var newSnapshot = NSDiffableDataSourceSnapshot<SectionType, ItemType>()
        newSnapshot.appendSections(data.map { $0.section })

        data.forEach { section in
            newSnapshot.appendItems(section.items, toSection: section.section)
        }

        let isInitialApply = collectionViewHolder.dataSource.snapshot().sectionIdentifiers.isEmpty
        collectionViewHolder.dataSource.apply(newSnapshot, animatingDifferences: !isInitialApply)
    }

    private func makeDeleteAction(
        style: UIContextualAction.Style = .destructive,
        title: String = "Delete",
        indexPath: IndexPath,
        section: SectionType,
        item: ItemType
    ) -> UIContextualAction {
        let action = UIContextualAction(style: style, title: title) { _, _, handler in
            onRowDeleted((
                sectionIndex: indexPath.section,
                itemIndex: indexPath.row,
                section: section,
                item: item
            ))

            handler(true)
        }

        if let backgroundColor = listConfiguration.edit.deleteButtonBackgroundColor {
            action.backgroundColor = UIColor(backgroundColor)
        }

        action.image = listConfiguration.edit.deleteButtonImage

        return action
    }
}
