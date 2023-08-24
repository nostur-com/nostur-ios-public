//
//  SmoothList.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/04/2023.
//

import SwiftUI
import Nuke
import Combine

enum SingleSection: CaseIterable {
    case main
}

// The main feed
// It's a UICollectionView in a UIViewControllerRepresentable because
// plain SwiftUI ScrollView/LazyVStacks doesn't give smooth scrolling
// and is lacking features to load new posts at top while maintaining
// scroll position

struct SmoothList: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    typealias CollectionViewHolderType = CViewHolder
    
    var dim: DIMENSIONS
    var lvm: LVM
    
    init(lvm:LVM, dim:DIMENSIONS) {
        self.lvm = lvm
        self.dim = dim
    }
    
    func makeCoordinator() -> Coordinator {
        L.sl.debug("⭐️ SmoothList \(self.lvm.id) \(self.lvm.pubkey?.short ?? "-"): makeCoordinator")
        return Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIViewControllerType {
        L.sl.debug("⭐️ SmoothList \(context.coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): makeUIViewController")
        let viewController = UIViewControllerType()
        let collectionViewHolder = makeCollectionViewHolder(parent: viewController, coordinator:context.coordinator)
        context.coordinator.collectionViewHolder = collectionViewHolder
        
        if context.coordinator.collectionViewHolder != nil {
            configureCollectionView(context: context)
        }
        return viewController
    }
    
    private func configureCollectionView(context: Context) {
        guard let cvh = context.coordinator.collectionViewHolder else { return }
        
        // configure lvm
        context.coordinator.lvm = lvm
        context.coordinator.data = lvm.nrPostLeafs
        
        // load posts
        refresh(cvh, coordinator: context.coordinator)
        
        // set up 'scroll to'- listener
        receiveNotification(.shouldScrollToFirstUnread)
            .sink { _ in
                guard context.coordinator.lvm.viewIsVisible else { return }
                guard context.coordinator.lvm.lvmCounter.count > 0 else {
                    // if no unread, scroll to top
                    if !context.coordinator.lvm.nrPostLeafs.isEmpty {
                        cvh.collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
                    }
                    return
                }
                guard let row = context.coordinator.lvm.lastReadIdIndex else { return }
                cvh.collectionView.scrollToItem(at: IndexPath(item: max(0,row-1), section: 0), at: .top, animated: true)
            }
            .store(in: &context.coordinator.subscriptions)

        receiveNotification(.shouldScrollToTop)
            .sink { _ in
                guard context.coordinator.lvm.viewIsVisible else { return }
                if !context.coordinator.lvm.nrPostLeafs.isEmpty {
                    cvh.collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
                }
            }
            .store(in: &context.coordinator.subscriptions)
    }
    
    private func makeCollectionViewHolder(parent viewController: UIViewControllerType,
                                          coordinator: Coordinator) -> CollectionViewHolderType {
        L.sl.info("⭐️ SmoothList \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): makeCollectionViewHolder")
        let collectionViewHolder = CViewHolder(coordinator: coordinator) { uiCollectionView in
            //            uiCollectionView.translatesAutoresizingMaskIntoConstraints = false
            uiCollectionView.translatesAutoresizingMaskIntoConstraints = false
            //            uiCollectionView.backgroundColor = UIColor.yellow // UIColor(named: "ListBackground")
            viewController.view.addSubview(uiCollectionView)
            
            NSLayoutConstraint.activate([
                viewController.view.leadingAnchor.constraint(equalTo: uiCollectionView.leadingAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: uiCollectionView.trailingAnchor),
                viewController.view.topAnchor.constraint(equalTo: uiCollectionView.topAnchor), // Add this line
                viewController.view.bottomAnchor.constraint(equalTo: uiCollectionView.bottomAnchor)
            ])
        }
        return collectionViewHolder
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        L.sl.info("⭐️ SmoothList \(context.coordinator.lvm.id): OLD updateUIViewController \(context.coordinator.lvm.uuid)")
        L.sl.info("⭐️ SmoothList \(self.lvm.id): NEW updateUIViewController \(self.lvm.uuid)")
        
        if (lvm.uuid != context.coordinator.lvm.uuid) {
            // set up new
            if context.coordinator.collectionViewHolder != nil {
                configureCollectionView(context: context)
            }
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: Self.UIViewControllerType, coordinator: Self.Coordinator) {
        L.sl.debug("⭐️ SmoothList. dismantleUIViewController \(coordinator.lvm.id) \(coordinator.lvm.pubkey?.short ?? "-")")
        coordinator.subscriptions.removeAll()
    }
    
    func refresh(_ collectionViewHolder:CViewHolder, coordinator:Coordinator) {
        L.sl.info("⭐️ SmoothList \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): refresh")
        coordinator.subscriptions.removeAll()
        collectionViewHolder.dataSource = collectionViewHolder.createDataSource(coordinator: coordinator)
        var snapshot = NSDiffableDataSourceSnapshot<SingleSection, String>()
        snapshot.appendSections([SingleSection.main])
        snapshot.appendItems(coordinator.data.map { $0.id }, toSection: .main)
        collectionViewHolder.dataSource?.apply(snapshot, animatingDifferences: false)

        coordinator.lvm.$nrPostLeafs
            .sink { data in
                coordinator.data = data
                guard let dataSource = collectionViewHolder.dataSource else { return }
                let currentNumberOfItems = dataSource.snapshot().numberOfItems(inSection: .main)
                let isInitialApply =  currentNumberOfItems == 0
                var snapshot = NSDiffableDataSourceSnapshot<SingleSection, String>()
                snapshot.appendSections([SingleSection.main])
                snapshot.appendItems(data.map { $0.id }, toSection: .main)
                
                let restoreToId:String? = collectionViewHolder.collectionView.contentOffset.y == 0 ? dataSource.snapshot(for: .main).items.first : nil
                                
                if !SettingsStore.shared.autoScroll && restoreToId != nil {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                }
                
                // Never animate on the first load (!isInitialApply)
                // Then only animate if we don't restore to top (restoreTopId == nil)
                // or if we have auto scroll enabled (SettingsStore.shared.autoScroll)
                let shouldAnimate = !isInitialApply && (restoreToId == nil || SettingsStore.shared.autoScroll)
                
                let beforeCount = !isInitialApply ? currentNumberOfItems : 0
                
                L.sl.info("⭐️⭐️ SmoothList \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): \(currentNumberOfItems) → \(data.count)")
                
                dataSource.apply(snapshot, animatingDifferences: shouldAnimate) {
                    if (isInitialApply) { // Scroll to initial position
                        // ON FIRST LOAD: SCROLL TO SOME INDEX (RESTORE)
                        if (coordinator.lvm.initialIndex > 4) {
                            L.sl.info("⭐️⭐️⭐️ SmoothList \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): initial - scrollToItem: \(coordinator.lvm.initialIndex.description) posts: \(data.count)")
                            coordinator.lvm.isAtTop = false
                            collectionViewHolder.collectionView.scrollToItem(at: IndexPath(item: coordinator.lvm.initialIndex, section: 0), at: .top, animated: false)
                        }
                        else if (collectionViewHolder.collectionView.contentOffset.y == 0) {
                            // IF WE ARE AT TOP, ALWAYS SET COUNTER TO 0
//                            L.sl.info("⭐️⭐️⭐️ SmoothList \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): Initial - posts: \(data.count) - force counter to 0")
//                            coordinator.lvm.lvmCounter.count = 0 // Publishing changes from within view updates is not allowed, this will cause undefined behavior.
                            coordinator.lvm.lastReadId = coordinator.lvm.nrPostLeafs.first?.id
                        }
                    }
                    else {
                        // KEEP POSITION AFTER INSERT, IF AUTOSCROLL IS DISABLED
                        if !SettingsStore.shared.autoScroll {
                            if let restoreToId {
                                if let restoreIndex = data.firstIndex(where: { $0.id == restoreToId }) {
                                    L.sl.info("⭐️⭐️ SmoothList \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): adding \(data.count - beforeCount) posts - scrollToItem: \(restoreIndex), restoreToId: \(restoreToId)")
                                    collectionViewHolder.collectionView.scrollToItem(at: IndexPath(item: restoreIndex, section: 0), at: .top, animated: false)
                                }
                            }
                        }
                        if !SettingsStore.shared.autoScroll && restoreToId != nil {
                            CATransaction.commit()
                        }
                    }
                }
            }
            .store(in: &coordinator.subscriptions)
    }
 
    final class Coordinator: NSObject, UICollectionViewDelegate, UIScrollViewDelegate, UICollectionViewDataSourcePrefetching, UICollectionViewDelegateFlowLayout {
        var subscriptions = Set<AnyCancellable>()
        let parent: SmoothList
        var lvm: LVM
        var data:[NRPost] = []
        var collectionViewHolder: CollectionViewHolderType?
        var scrollTimer: Timer?
        var prefetcher:ImagePrefetcher
        var prefetcherPFP:ImagePrefetcher
        
        private var lastCalledTimestamp: TimeInterval = 0
        private let debounceInterval: TimeInterval = 0.3 // Adjust this value to control the throttling
        
        
        init(parent: SmoothList) {
            self.parent = parent
            self.lvm = parent.lvm
            
            self.prefetcher = ImagePrefetcher(pipeline: ImageProcessing.shared.content)
            self.prefetcher.priority = .normal
            
            self.prefetcherPFP = ImagePrefetcher(pipeline: ImageProcessing.shared.pfp)
            self.prefetcherPFP.priority = .high
        }
        
        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let imageWidth = parent.dim.availableNoteRowImageWidth()
            var imageRequests:[ImageRequest] = []
            var imageRequestsPFP:[ImageRequest] = []
            //            var imageRequestsPFPnotFollowing:[ImageRequest] = []
            
            for indexPath in indexPaths {
                guard let item = data[safe: indexPath.row] else { continue }
                
                if !item.missingPs.isEmpty {
                    DataProvider.shared().bg.perform {
                        EventRelationsQueue.shared.addAwaitingEvent(item.event, debugInfo: "SmoothList.001 - missingPs: \(item.missingPs.count)")
                        QueuedFetcher.shared.enqueue(pTags: item.missingPs)
                        L.fetching.info("🟠🟠 Prefetcher: \(item.missingPs.count) missing contacts (event.pubkey or event.pTags) for: \(item.id)")
                    }
                }
                
                if let picture = item.contact?.pictureUrl, picture.prefix(7) != "http://" {
                    imageRequestsPFP.append(pfpImageRequestFor(picture))
                }
                
                imageRequestsPFP.append(contentsOf: item
                    .parentPosts
                    .compactMap { $0.contact?.pictureUrl }
                    .filter { $0.prefix(7) != "http://" }
                    .map { pfpImageRequestFor($0) }
                )
                
                
                for imageUrl in item.imageUrls.filter({ $0.absoluteString.prefix(7) != "http://" })
                {
                    imageRequests.append(ImageRequest(url: imageUrl,
                                                      processors: [.resize(width: imageWidth, upscale: true)],
                                                      userInfo: [.scaleKey: UIScreen.main.scale]))
                }
                
                imageRequests.append(contentsOf: item
                    .parentPosts
                    .reduce([ImageRequest](), { partialResult, item in
                        return partialResult + item.imageUrls
                            .filter { $0.absoluteString.prefix(7) != "http://" }
                            .map { ImageRequest(url: $0,
                                                processors: [.resize(width: imageWidth, upscale: true)],
                                                userInfo: [.scaleKey: UIScreen.main.scale]) }
                    })
                )
                
                for url in item.linkPreviewURLs.filter({ $0.absoluteString.prefix(7) != "http://" }) {
                    fetchMetaTags(url: url) { result in
                        do {
                            let tags = try result.get()
                            LinkPreviewCache.shared.setObject(for: url, value: tags)
                            L.og.info("✓✓ Loaded link preview meta tags from \(url)")
                        }
                        catch { }
                    }
                }
            }
            if !imageRequests.isEmpty {
                prefetcher.startPrefetching(with: imageRequests)
            }
            if !imageRequestsPFP.isEmpty {
                prefetcherPFP.startPrefetching(with: imageRequestsPFP)
            }
        }
        
        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            let imageWidth = parent.dim.availableNoteRowImageWidth()
            var imageRequests:[ImageRequest] = []
            var imageRequestsPFP:[ImageRequest] = []
            
            for indexPath in indexPaths {
                guard let item = data[safe: indexPath.row] else { continue }
                
                if !item.missingPs.isEmpty {
                    QueuedFetcher.shared.dequeue(pTags: item.missingPs)
                }
                
                if let picture = item.contact?.pictureUrl, picture.prefix(7) != "http://" {
                    imageRequestsPFP.append(pfpImageRequestFor(picture))
                }
                
                imageRequestsPFP.append(contentsOf: item
                    .parentPosts
                    .compactMap { $0.contact?.pictureUrl }
                    .filter { $0.prefix(7) != "http://" }
                    .map { pfpImageRequestFor($0) }
                )
                                
                for imageUrl in item.imageUrls.filter( { $0.absoluteString.prefix(7) != "http://" })
                {
                    imageRequests.append(ImageRequest(url: imageUrl,
                                                      processors: [.resize(width: imageWidth, upscale: true)],
                                                      userInfo: [.scaleKey: UIScreen.main.scale]))
                }
                
                imageRequests.append(contentsOf: item
                    .parentPosts
                    .reduce([ImageRequest](), { partialResult, item in
                        return partialResult + item.imageUrls
                            .filter { $0.absoluteString.prefix(7) != "http://" }
                            .map { ImageRequest(url: $0,
                                                processors: [.resize(width: imageWidth, upscale: true)],
                                                userInfo: [.scaleKey: UIScreen.main.scale]) }
                    })
                )
            }
            if (!imageRequests.isEmpty) {
                prefetcher.stopPrefetching(with: imageRequests)
            }
            if !imageRequestsPFP.isEmpty {
                prefetcherPFP.stopPrefetching(with: imageRequestsPFP)
            }
        }
        
        //        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        //            let cellWidth = collectionView.bounds.size.width - (parent.fullWidthImages ? 0 : 10)
        //            guard let item = parent.data[safe: indexPath.row] else { return CGSize(width: cellWidth, height: 250.0) }
        //
        //            let mediaElements = item.renderedElements.filter {
        //                if case .image = $0 {
        //                        return true
        //                }
        //                if case .video = $0 {
        //                        return true
        //                }
        //                if case .linkPreview = $0 {
        //                        return true
        //                }
        //                return false
        //            }
        //
        //            // Count every image/video/linkpreview as 250. every parent or post as 150
        //            let height = Double((mediaElements.count * 250) + (item.threadPostsCount) * 150)
        //            print("🟢🟢 height estimated at: \(height)" )
        //            return CGSize(width: cellWidth, height: height)
        //        }
        
        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            
            if let lastAppearedId = data[safe: indexPath.row]?.id {
                lvm.lastAppearedIdSubject.send(lastAppearedId)
            }
            
            // SAME CODE BUT THROTTLED, DISABLED....
            // Calculate the time since the last call
//            let currentTime = Date().timeIntervalSince1970
//            let timeSinceLastCall = currentTime - lastCalledTimestamp
//
//            // Check if the debounceInterval has passed
//            if timeSinceLastCall > debounceInterval {
//                // Update the lastCalledTimestamp
//                lastCalledTimestamp = currentTime
//
//                // Your throttled code here
//                if let lastAppearedId = lvm.nrPostLeafs[safe: indexPath.row]?.id {
//                    lvm.lastAppearedIdSubject.send(lastAppearedId)
//                }
//            }
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            scrollTimer?.invalidate()
            scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.processScrollViewDidScroll(scrollView)
            }
            
            guard !IS_CATALYST else { return }
            if !scrollDirectionDetermined {
                let translation = scrollView.panGestureRecognizer.translation(in: scrollView)
                if translation.y > 0 {
                    sendNotification(.scrollingUp)
                    scrollDirectionDetermined = true
                }
                else if translation.y < 0 {
                    sendNotification(.scrollingDown)
                    scrollDirectionDetermined = true
                }
            }
        }

        func processScrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let indexPaths = collectionViewHolder?.collectionView.indexPathsForVisibleItems else {
                return
            }
            if scrollView.contentOffset.y > 150 {
                if lvm.isAtTop {
                    lvm.isAtTop = false
                }
            }
            else {
                lvm.isAtTop = true
                
                if let firstIndex = indexPaths.min(by: { $0.row < $1.row }) {
                    if firstIndex.row < 1 { // not sure why just index 0 doesn't work 1% of the time
                        lvm.lvmCounter.count = 0 // Publishing changes from within view updates is not allowed, this will cause undefined behavior.
                    }
                    
                    if let lastAppearedId = data[safe: firstIndex.row]?.id {
                        lvm.lastAppearedIdSubject.send(lastAppearedId)
                    }
                }
            }
            
            lvm.postsAppearedSubject.send(indexPaths.compactMap { data[safe: $0.row]?.id })
        }
        
        private var scrollDirectionDetermined = false

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            scrollDirectionDetermined = false
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            scrollDirectionDetermined = false
        }
        
//        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
//            if scrollView.panGestureRecognizer.translation(in: scrollView).y < 0 {
//               print("Dragging up")
//
//            } else {
//                print("Dragging down")
//            }
//        }
        
        public var PostOrThreadCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, NRPost> = {
            .init { cell, indexPath, nrPost in
                cell.contentConfiguration = UIHostingConfiguration {
                    PostOrThread(nrPost: nrPost)
                }
                .background(Color("ListBackground")) // Between and around every PostOrThread (NoteRows)
                .margins(.vertical, 5)
                .margins(.horizontal, 0)
            }
        }()
        
        public var MissingCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, String> = {
            .init { cell, indexPath, item in
                cell.contentConfiguration = UIHostingConfiguration {
                    Text(item)
                        .hCentered()
                }
                .background(Color("ListBackground")) // Between and around every PostOrThread (NoteRows)
                .margins(.vertical, 5)
                .margins(.horizontal, 0)
            }
        }()
    }
}


func debounce(delay: TimeInterval, action: @escaping (() -> Void)) -> () -> Void {
    var lastRun: Date = Date()
    let queue = DispatchQueue.main
    return {
        let now = Date()
        let deadline: DispatchTime = .now() + delay
        lastRun = now
        queue.asyncAfter(deadline: deadline) {
            let sinceLastRun = now.timeIntervalSince(lastRun)
            guard sinceLastRun >= delay else { return }
            action()
        }
    }
}

final class CViewHolder {
    let collectionView: UICollectionView
    typealias DataSourceType = UICollectionViewDiffableDataSource<SingleSection, String>
    var dataSource: DataSourceType?
    private let coordinator: SmoothList.Coordinator?
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
        
        layout.configuration.scrollDirection = .vertical
        
        //        let flowLayout = UICollectionViewFlowLayout()
        //        flowLayout.estimatedItemSize = CGSize(width: UIScreen.main.bounds.width - 10, height: 250.0)
        //        flowLayout.scrollDirection = .vertical
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = UIColor(named: "ListBackground") // This color flashes visible for a milisecond and is then covered by all other things
        collectionView.allowsSelection = false
        collectionView.delegate = coordinator
        collectionView.prefetchDataSource = coordinator
        collectionView.isPrefetchingEnabled = true
//        collectionView.selfSizingInvalidation = .enabledIncludingConstraints
        collectionView.selfSizingInvalidation = .enabled
        collectionView.isOpaque = true
        collectionView.dragInteractionEnabled = false
        collectionView.allowsSelection = false
        collectionView.allowsFocus = false
        onInitialized(collectionView)
    }

    func createDataSource(coordinator: SmoothList.Coordinator) -> DataSourceType {
        L.sl.debug("⭐️ SmoothList \(coordinator.lvm.id) \(coordinator.lvm.pubkey?.short ?? "-"): CViewHolder.createDataSource")
        return UICollectionViewDiffableDataSource<SingleSection, String>(
            collectionView: collectionView,
            cellProvider: { collectionView, indexPath, identifier -> UICollectionViewCell? in
                guard let nrPost = coordinator.data.first(where: { $0.id == identifier }) else {
                    return collectionView.dequeueConfiguredReusableCell(using: coordinator.MissingCellRegistration, for: indexPath, item: "🧨")
                }
                return collectionView.dequeueConfiguredReusableCell(using: coordinator.PostOrThreadCellRegistration, for: indexPath, item: nrPost)
            }
        )
    }
}

func pfpImageRequestFor(_ picture:String) -> ImageRequest {
    
    //    thumbOptions.createThumbnailFromImageAlways = true
    //    thumbOptions.shouldCacheImmediately = true
    if !SettingsStore.shared.animatedPFPenabled || picture.suffix(4) != ".gif" {
        return ImageRequest(url: URL(string:picture),
                            //                            userInfo: [.thumbnailKey: thumbOptions],
                            processors: [
                                .resize(size: CGSize(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_HEIGHT),
                                        unit: .points,
                                        contentMode: .aspectFill,
                                        crop: true,
                                        upscale: true)
                            ],
                            userInfo: [.scaleKey: UIScreen.main.scale]
                            //                            userInfo: [.scaleKey: 1, .thumbnailKey: thumbOptions]
                            //                            userInfo: [.scaleKey: UIScreen.main.scale, .thumbnailKey: thumbOptions]
        )
    }
    return ImageRequest(url: URL(string:picture))
}
