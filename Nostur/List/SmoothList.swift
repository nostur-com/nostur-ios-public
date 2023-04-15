//
//  SmoothList.swift Super smooth scrolling
//  Nostur
//
//  Created by Fabian Lachman on 11/04/2023.
//

import SwiftUI

let SMOOTHLIST_AUTOSCROLL_OFFSET = 1.0

enum SingleSection: CaseIterable {
    case main
}

struct SmoothList: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    typealias CollectionViewHolderType = CViewHolder
    typealias RowAppearedCallback = ((sectionIndex: Int, itemIndex: Int, item: VPost)) -> Void
    typealias FinishedScrollingCallback = (Bool) -> Void
    
    @Binding var needsRefresh: Bool
    @Binding var needsScrollToTop: Bool
    @Binding var needsScrollToIndex: Int?
    @Binding var data: [VPost]
    @Binding var autoScroll: Bool
    private var onRowAppeared: RowAppearedCallback?
    private var onFinishedScrolling: FinishedScrollingCallback?
    
    init(needsRefresh: Binding<Bool>, needsScrollToTop:Binding<Bool>, needsScrollToIndex:Binding<Int?>, data: Binding<[VPost]>, autoScroll: Binding<Bool>, onRowAppeared: RowAppearedCallback? = nil, onFinishedScrolling: FinishedScrollingCallback? = nil) {
        self._needsRefresh = needsRefresh
        self._needsScrollToTop = needsScrollToTop
        self._needsScrollToIndex = needsScrollToIndex
        self._data = data
        self._autoScroll = autoScroll
        self.onRowAppeared = onRowAppeared
        self.onFinishedScrolling = onFinishedScrolling
    }
    
    func makeUIViewController(context: Context) -> UIViewControllerType {
        let viewController = UIViewControllerType()
        let collectionViewHolder = makeCollectionViewHolder(parent: viewController, coordinator:context.coordinator)
        context.coordinator.collectionViewHolder = collectionViewHolder
        return viewController
    }
    
    private func makeCollectionViewHolder(parent viewController: UIViewControllerType,
                                          coordinator: Coordinator) -> CollectionViewHolderType {
        
        let collectionViewHolder = CViewHolder(coordinator: coordinator) { uiCollectionView in
//            uiCollectionView.translatesAutoresizingMaskIntoConstraints = false
            uiCollectionView.translatesAutoresizingMaskIntoConstraints = false
//            uiCollectionView.backgroundColor = UIColor.yellow // UIColor(named: "ListBackground")
            viewController.view.addSubview(uiCollectionView)
//            viewController.view.backgroundColor = UIColor.blue
            
            NSLayoutConstraint.activate([
                viewController.view.leadingAnchor.constraint(equalTo: uiCollectionView.leadingAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: uiCollectionView.trailingAnchor),
                viewController.view.topAnchor.constraint(equalTo: uiCollectionView.topAnchor), // Add this line
                viewController.view.bottomAnchor.constraint(equalTo: uiCollectionView.bottomAnchor)
            ])
        }
        return collectionViewHolder
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if needsRefresh, let collectionViewHolder = context.coordinator.collectionViewHolder {
                refreshData(collectionViewHolder)
                Task {
                    needsRefresh = false
                }
            }
            
            if needsScrollToTop, let ch = context.coordinator.collectionViewHolder {
                // do the scroll
                ch.collectionView.setContentOffset(CGPoint(x:0, y: autoScroll ? 0 : SMOOTHLIST_AUTOSCROLL_OFFSET), animated: true)
                Task {
                    needsScrollToTop = false
                }
            }
            
            if needsScrollToIndex != nil, let ch = context.coordinator.collectionViewHolder {
                if (needsScrollToIndex == 0) {
                    ch.collectionView.setContentOffset(CGPoint(x:0, y: autoScroll ? 0 : SMOOTHLIST_AUTOSCROLL_OFFSET), animated: true)
                }
                else {
                    ch.collectionView.scrollToItem(at: IndexPath(item: needsScrollToIndex!, section: 0), at: .top, animated: false)
                }
                
                Task {
                    needsScrollToIndex = nil
                }
            }
        }
    }
    
    private func refreshData(_ collectionViewHolder: CollectionViewHolderType) {
        var newSnapshot = NSDiffableDataSourceSnapshot<SingleSection, String>()
        newSnapshot.appendSections([SingleSection.main])
        newSnapshot.appendItems(data.map { $0.id }, toSection: SingleSection.main)

        let isInitialApply = collectionViewHolder.dataSource.snapshot().sectionIdentifiers.isEmpty

        collectionViewHolder.dataSource.apply(newSnapshot, animatingDifferences: !isInitialApply) {
            if (isInitialApply) { // Scroll to initial position
                DispatchQueue.main.async {
                    //                    guard let self = self else { return }
                    //                    print("❤️❤️ \(self.needsScrollToIndex)")
                    if (self.needsScrollToIndex != nil) && (self.needsScrollToIndex! > 4) {
                        //                        print("❤️❤️ \(self.needsScrollToIndex) 1")
                        collectionViewHolder.collectionView.scrollToItem(at: IndexPath(item: self.needsScrollToIndex!, section: 0), at: .top, animated: false)
                        
                        Task {
                            self.needsScrollToIndex = nil
                        }
                    }
                    else {
                        if !self.autoScroll {
                            //                            print("❤️❤️ no autoscroll please, offset a little")
                            collectionViewHolder.collectionView.setContentOffset(CGPoint(x:0, y: SMOOTHLIST_AUTOSCROLL_OFFSET), animated: false)
                        }
                    }
                }
            }
        }
    }
    
    final class Coordinator: NSObject, UICollectionViewDelegate, UIScrollViewDelegate, UICollectionViewDataSourcePrefetching { //, UICollectionViewDataSource {
        let parent: SmoothList
        var collectionViewHolder: CollectionViewHolderType?
        var scrollTimer: Timer?

        init(parent: SmoothList) {
            self.parent = parent
        }
        
        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            for indexPath in indexPaths {
                guard let item = parent.data[safe: indexPath.row] else { continue }
                for url in item.linkPreviewURLs {
                    fetchMetaTags(url: url) { result in
                        do {
                            let tags = try result.get()
                            LinkPreviewCache.shared.setObject(for: url, value: tags)
                            print("✓✓ Loaded link preview meta tags from \(url)")
                        }
                        catch {
                            
                        }
                    }
                }
            }
        }
        
        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            if let item = parent.data[safe: indexPath.row] {
                parent.onRowAppeared?((sectionIndex: indexPath.section, itemIndex: indexPath.row,  item: item))
            }
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            scrollTimer?.invalidate()
            scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                self?.processScrollViewDidScroll(scrollView)
            }
        }
        
        func processScrollViewDidScroll(_ scrollView: UIScrollView) {
            if let indexPaths = collectionViewHolder?.collectionView.indexPathsForVisibleItems {
                print(indexPaths)
            }
            if scrollView.contentOffset.y > 150 {
                print("IS AT TOP FALSE")
                parent.onFinishedScrolling?(false) // didFinish and isAtTop=false

            }
            else {
                print("IS AT TOP TRUE")
                parent.onFinishedScrolling?(true) // didFinish and isAtTop=true
                
                if (!parent.autoScroll) && (scrollView.contentOffset.y < SMOOTHLIST_AUTOSCROLL_OFFSET) {
                    // if really at top, push back a little, so new items inserted at top don't push all down
                    //                    scrollView.layoutIfNeeded();
                    scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: SMOOTHLIST_AUTOSCROLL_OFFSET), animated: true)
                }
            }
        }
    }
}

final class CViewHolder {
    let collectionView: UICollectionView
    typealias DataSourceType = DataSourcy<SingleSection, String>
    private(set) lazy var dataSource: DataSourceType = createDataSource()
    private let coordinator: SmoothList.Coordinator
    private var layoutListConfiguration = UICollectionLayoutListConfiguration(appearance: .plain)
    
    init(
        coordinator: SmoothList.Coordinator,
        onInitialized: @escaping (UICollectionView) -> Void
    ) {
        self.coordinator = coordinator
        
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.showsSeparators = false
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
            section.contentInsets = .zero
            return section
        }
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        //        collectionView.backgroundColor = .systemGroupedBackground
        //        collectionView.backgroundColor = UIColor(named: "ListBackground")
        collectionView.allowsSelection = false
        collectionView.delegate = coordinator
        collectionView.prefetchDataSource = coordinator
        //        collectionView.backgroundColor = UIColor.brown
        onInitialized(collectionView)
    }
    
    final class DataSourcy<
        SectionType: Hashable,
        ItemType: Hashable
    >: UICollectionViewDiffableDataSource<SectionType, ItemType> {
        override func indexTitles(for collectionView: UICollectionView) -> [String]? {
            snapshot().sectionIdentifiers
                .compactMap {
                    ($0 as? CustomStringConvertible)?.description
                }
        }
    }
    
    private var PostOrThreadCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, VPost> = {
        .init { cell, indexPath, vPost in
            cell.contentConfiguration = UIHostingConfiguration {
                PostOrThread(vPost: vPost)
                    .boxShadow()
                    .padding(10)
            }
            .background(Color("ListBackground"))
            .margins(.all, 0)
            //            cell.layer.shouldRasterize = true
            //            cell.layer.rasterizationScale = UIScreen.main.scale
        }
    }()
    
    private var MissingCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, String> = {
        .init { cell, indexPath, item in
            cell.contentConfiguration = UIHostingConfiguration {
                Text(item)
                    .hCentered()
            }
            .background(Color("ListBackground"))
            .margins(.all, 0)
        }
    }()
    
    private func createDataSource() -> DataSourceType {
        DataSourcy<SingleSection, String>(
            collectionView: collectionView,
            cellProvider: { [weak self] collectionView, indexPath, identifier -> UICollectionViewCell? in
                guard let self = self else { return nil }
                
                guard let vPost = self.coordinator.parent.data.first(where: { $0.id == identifier }) else {
                    return self.collectionView.dequeueConfiguredReusableCell(using: MissingCellRegistration, for: indexPath, item: "🧨")
                }
                
                return self.collectionView.dequeueConfiguredReusableCell(using: PostOrThreadCellRegistration, for: indexPath, item: vPost)
                
                
                // TODO: Implement this
                //                if self.collectionView.isLastItem(indexPath) {
                //                    self.onLoadMore()
                //                }
            }
        )
    }
}


struct SmoothList_PReviews: PreviewProvider {
    @State static var needsRefresh = false
    @State static var needsScrollToTop = false
    @State static var needsScrollToIndex:Int? = nil
    @State static var autoScroll = true
    @State static var vPosts = PreviewFetcher
        .fetchEvents(NosturState.shared.followingPublicKeys, kind: 1)
        .map {
            $0.parentEvents = Event.getParentEvents($0)
            return $0
        }
        .filter(onlyRootOrReplyingToFollower)
        .compactMap { $0.toVPost() }
    
    static var previews: some View {
        VStack(spacing:0) {
            SmoothList(needsRefresh: $needsRefresh, needsScrollToTop: $needsScrollToTop, needsScrollToIndex: $needsScrollToIndex, data: $vPosts, autoScroll: $autoScroll)
                .onAppear {
                    needsRefresh = true
                }
        }
        .withPreviewEnvironment()
    }
}
