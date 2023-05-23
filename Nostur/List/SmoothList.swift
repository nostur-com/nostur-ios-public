//
//  SmoothList.swift Super smooth scrolling
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
        L.sl.debug("⭐️ SmoothList: makeCoordinator")
        return Coordinator(parent: self, lvm: self.lvm)
    }
    
    func makeUIViewController(context: Context) -> UIViewControllerType {
        L.sl.debug("⭐️ SmoothList: makeUIViewController")
        let viewController = UIViewControllerType()
        let collectionViewHolder = makeCollectionViewHolder(parent: viewController, coordinator:context.coordinator)
        context.coordinator.collectionViewHolder = collectionViewHolder
        return viewController
    }
    
    private func makeCollectionViewHolder(parent viewController: UIViewControllerType,
                                          coordinator: Coordinator) -> CollectionViewHolderType {
        L.sl.debug("⭐️ SmoothList: makeCollectionViewHolder")
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
        L.sl.debug("⭐️ SmoothList: updateUIViewController")
        // TODO: add check to know of we should refresh???
        if let cvh = context.coordinator.collectionViewHolder {
            context.coordinator.lvm = lvm
            refresh(cvh, coordinator: context.coordinator)
        }
    }
    
    func refresh(_ collectionViewHolder:CViewHolder, coordinator:Coordinator) {
        L.sl.debug("⭐️ SmoothList: refresh")
        coordinator.subscriptions.removeAll()
        collectionViewHolder.dataSource = collectionViewHolder.createDataSource(lvm: coordinator.lvm)

        coordinator.lvm.didSetNrPostLeafs
            .sink {
                guard let dataSource = collectionViewHolder.dataSource else { return }
                let posts = coordinator.lvm.nrPostLeafs
                var snapshot = NSDiffableDataSourceSnapshot<SingleSection, String>()
                snapshot.appendSections([SingleSection.main])
                snapshot.appendItems(posts.map { $0.id }, toSection: SingleSection.main)
                
                let isInitialApply = dataSource.snapshot().sectionIdentifiers.isEmpty
                
                L.sl.debug("⭐️ SmoothList: $_nrPostLeafs.sink -> dataSource.apply(snapshot) (posts: \(posts.count)) (isInitialApply: \(isInitialApply))")
                
                let restoreTopId:String? = collectionViewHolder.collectionView.contentOffset.y == 0 ? dataSource.snapshot(for: .main).items.first : nil
                
                L.sl.debug("⭐️ SmoothList: restoreTopId: \(restoreTopId ?? "-") contentOffset.y: \(collectionViewHolder.collectionView.contentOffset.y.description)")
                
                if !SettingsStore.shared.autoScroll && restoreTopId != nil {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                }
                
                // Never animate on the first load (!isInitialApply)
                // Then only animate if we don't restore to top (restoreTopId == nil)
                // or if we have auto scroll enabled (SettingsStore.shared.autoScroll)
                let shouldAnimate = !isInitialApply && (restoreTopId == nil || SettingsStore.shared.autoScroll)
                
                dataSource.apply(snapshot, animatingDifferences: shouldAnimate) {
                    if (isInitialApply) { // Scroll to initial position
                        // ON FIRST LOAD: SCROLL TO SOME INDEX (RESTORE)
                        if (coordinator.lvm.initialIndex > 4) {
                            L.sl.debug("⭐️ SmoothList:   ↳  dataSource.apply - scrollToItem: \(coordinator.lvm.initialIndex.description)")
                            coordinator.lvm.isAtTop = false
                            collectionViewHolder.collectionView.scrollToItem(at: IndexPath(item: coordinator.lvm.initialIndex, section: 0), at: .top, animated: false)
                        }
                        else if (collectionViewHolder.collectionView.contentOffset.y == 0) {
                            // IF WE ARE AT TOP, ALWAYS SET COUNTER TO 0
                            L.sl.debug("⭐️ SmoothList:   ↳  dataSource.apply - contentOffset.y == 0. --> force counter to 0")
                            coordinator.lvm.lvmCounter.count = 0
                        }
                    }
                    else {
                        // KEEP POSITION AFTER INSERT, IF AUTOSCROLL IS DISABLED
                        if !SettingsStore.shared.autoScroll {
                            if let restoreTopId {
                                if let restoreIndex = posts.firstIndex(where: { $0.id == restoreTopId }) {
                                    L.sl.debug("⭐️ SmoothList: restoreTopId: \(restoreTopId) found at index: \(restoreIndex)")
                                    L.sl.debug("⭐️ SmoothList: scrollToItem: \(restoreIndex)")
                                    collectionViewHolder.collectionView.scrollToItem(at: IndexPath(item: restoreIndex, section: 0), at: .top, animated: false)
                                }
                            }
                        }
                        if !SettingsStore.shared.autoScroll && restoreTopId != nil {
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
        var collectionViewHolder: CollectionViewHolderType?
        var scrollTimer: Timer?
        var prefetcher:ImagePrefetcher
        var prefetcherPFP:ImagePrefetcher
        //        var prefetcherPFPnotFollowing:ImagePrefetcher
        
        private var lastCalledTimestamp: TimeInterval = 0
        private let debounceInterval: TimeInterval = 0.3 // Adjust this value to control the throttling
        
        
        init(parent: SmoothList, lvm: LVM) {
            self.lvm = lvm
            self.parent = parent
            
            self.prefetcher = ImagePrefetcher(pipeline: ImageProcessing.shared.content)
            self.prefetcher.priority = .normal
            
            self.prefetcherPFP = ImagePrefetcher(pipeline: ImageProcessing.shared.pfp)
            self.prefetcherPFP.priority = .high
            
            //            self.prefetcherPFPnotFollowing = ImagePrefetcher(pipeline: ImageProcessing.shared.pfpNotFollowing)
            //            self.prefetcherPFPnotFollowing.priority = .normal
        }
        
        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let imageWidth = parent.dim.availableNoteRowImageWidth()
            var imageRequests:[ImageRequest] = []
            var imageRequestsPFP:[ImageRequest] = []
            //            var imageRequestsPFPnotFollowing:[ImageRequest] = []
            
            for indexPath in indexPaths {
                guard let item = lvm.nrPostLeafs[safe: indexPath.row] else { continue }
                
                if item.missingPs.count > 0 {
                    EventRelationsQueue.shared.addAwaitingEvent(item.event, debugInfo: "SmoothList.001 - missingPs: \(item.missingPs.count)")
                    QueuedFetcher.shared.enqueue(pTags: item.missingPs)
                    print("🟠🟠 Prefetcher: \(item.missingPs.count) missing contacts (event.pubkey or event.pTags)")
                }
                
                if let picture = item.contact?.pictureUrl, picture.prefix(7) != "http://" {
                    imageRequestsPFP.append(pfpImageRequestFor(picture))
                }
                
                imageRequestsPFP.append(contentsOf: item
                    .parentPosts
                                        //                    .filter{ $0.contact?.following ?? false }
                    .compactMap { $0.contact?.pictureUrl }
                    .filter { $0.prefix(7) != "http://" }
                    .map { pfpImageRequestFor($0) }
                )
                
                //                imageRequestsPFPnotFollowing.append(contentsOf: item
                //                    .parentPosts
                //                    .filter{ !($0.contact?.following ?? false) }
                //                    .compactMap { $0.contact?.pictureUrl }
                //                    .filter { $0.prefix(7) != "http://" }
                //                    .map { imageRequestFor($0) }
                //                )
                
                
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
                            print("✓✓ Loaded link preview meta tags from \(url)")
                            if let image = tags["image"], image.prefix(7) != "http://" {
                                imageRequests.append(ImageRequest(url: URL(string:image),
                                                                  processors: [.resize(height: DIMENSIONS.PREVIEW_HEIGHT, upscale: true)],
                                                                  userInfo: [.scaleKey: UIScreen.main.scale]))
                            }
                        }
                        catch { }
                    }
                }
            }
            if imageRequests.count > 0 {
                //                print("prefetching for \(imageRequests.count)")
                prefetcher.startPrefetching(with: imageRequests)
            }
            if imageRequestsPFP.count > 0 {
                //                print("prefetching for PFP: \(imageRequestsPFP.count)")
                prefetcherPFP.startPrefetching(with: imageRequestsPFP)
            }
            //            if imageRequestsPFPnotFollowing.count > 0 {
            //                //                print("prefetching for PFP not following: \(imageRequestsPFPnotFollowing.count)")
            //                prefetcherPFPnotFollowing.startPrefetching(with: imageRequestsPFPnotFollowing)
            //            }
        }
        
        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            let imageWidth = parent.dim.availableNoteRowImageWidth()
            var imageRequests:[ImageRequest] = []
            var imageRequestsPFP:[ImageRequest] = []
            //            var imageRequestsPFPnotFollowing:[ImageRequest] = []
            
            for indexPath in indexPaths {
                guard let item = lvm.nrPostLeafs[safe: indexPath.row] else { continue }
                
                if item.missingPs.count > 0 {
                    QueuedFetcher.shared.dequeue(pTags: item.missingPs)
                }
                
                if let picture = item.contact?.pictureUrl, picture.prefix(7) != "http://" {
                    imageRequestsPFP.append(pfpImageRequestFor(picture))
                }
                
                imageRequestsPFP.append(contentsOf: item
                    .parentPosts
                                        //                    .filter{ $0.contact?.following ?? false }
                    .compactMap { $0.contact?.pictureUrl }
                    .filter { $0.prefix(7) != "http://" }
                    .map { pfpImageRequestFor($0) }
                )
                
                //                imageRequestsPFPnotFollowing.append(contentsOf: item
                //                    .parentPosts
                //                    .filter{ !($0.contact?.following ?? false) }
                //                    .compactMap { $0.contact?.pictureUrl }
                //                    .filter { $0.prefix(7) != "http://" }
                //                    .map { imageRequestFor($0) }
                //                )
                
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
                
                for url in item.linkPreviewURLs.filter({ $0.absoluteString.prefix(7) != "http://" }) {
                    if let tags = LinkPreviewCache.shared.retrieveObject(at: url) {
                        if let image = tags["image"], image.prefix(7) != "http://" {
                            imageRequests.append(ImageRequest(url: URL(string:image),
                                                              processors: [.resize(height: DIMENSIONS.PREVIEW_HEIGHT, upscale: true)],
                                                              userInfo: [.scaleKey: UIScreen.main.scale]))
                        }
                    }
                }
            }
            if (imageRequests.count > 0) {
                //                print("cancelling prefetch for \(imageRequests.count)")
                prefetcher.stopPrefetching(with: imageRequests)
            }
            if imageRequestsPFP.count > 0 {
                //                print("prefetching for PFP: \(imageRequestsPFP.count)")
                prefetcherPFP.stopPrefetching(with: imageRequestsPFP)
            }
            //            if imageRequestsPFPnotFollowing.count > 0 {
            //                //                print("prefetching for PFP not following: \(imageRequestsPFPnotFollowing.count)")
            //                prefetcherPFPnotFollowing.stopPrefetching(with: imageRequestsPFPnotFollowing)
            //            }
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
            
            if let lastAppearedId = lvm.nrPostLeafs[safe: indexPath.row]?.id {
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
        }
        
        func processScrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let indexPaths = collectionViewHolder?.collectionView.indexPathsForVisibleItems else {
                return
            }
            if scrollView.contentOffset.y > 150 {
                lvm.isAtTop = false
            }
            else {
                lvm.isAtTop = true
                if let firstIndex = indexPaths.min(by: { $0.row < $1.row }) {
                    if firstIndex.row < 1 { // not sure why just index 0 doesn't work 1% of the time
//                        print("COUNTER E: \(lvm.lvmCounter.count)")
                        lvm.lvmCounter.count = 0
//                        print("COUNTER EE: \(lvm.lvmCounter.count)")
                    }
                    
                    if let lastAppearedId = lvm.nrPostLeafs[safe: firstIndex.row]?.id {
                        lvm.lastAppearedIdSubject.send(lastAppearedId)
                    }
                }
                
//                if (!SettingsStore.shared.autoScroll) && (scrollView.contentOffset.y < SMOOTHLIST_AUTOSCROLL_OFFSET) {
//                    // if really at top, push back a little, so new items inserted at top don't push all down
//                    //                    scrollView.layoutIfNeeded();
//                    scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: SMOOTHLIST_AUTOSCROLL_OFFSET), animated: true)
//                }
            }
        }
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
    typealias DataSourceType = DataSourcy<SingleSection, String>
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
        collectionView.selfSizingInvalidation = .enabledIncludingConstraints
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
    
    private var PostOrThreadCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, NRPost> = {
        .init { cell, indexPath, nrPost in
            cell.contentConfiguration = UIHostingConfiguration {
                PostOrThread(nrPost: nrPost)
            }
            .background(Color("ListBackground")) // Between and around every PostOrThread (NoteRows)
            .margins(.all, 0)
        }
    }()
    
    private var MissingCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, String> = {
        .init { cell, indexPath, item in
            cell.contentConfiguration = UIHostingConfiguration {
                Text(item)
                    .hCentered()
            }
            .background(Color("ListBackground")) // Between and around every PostOrThread (NoteRows)
            .margins(.all, 0)
        }
    }()
    
    func createDataSource(lvm: LVM) -> DataSourceType {
        L.sl.debug("⭐️ SmoothList: CViewHolder.createDataSource")
        return DataSourcy<SingleSection, String>(
            collectionView: collectionView,
            cellProvider: { [weak self] collectionView, indexPath, identifier -> UICollectionViewCell? in
                guard let self = self else { return nil }
                guard let nrPost = lvm.nrPostLeafs.first(where: { $0.id == identifier }) else {
                    return collectionView.dequeueConfiguredReusableCell(using: MissingCellRegistration, for: indexPath, item: "🧨")
                }
                return collectionView.dequeueConfiguredReusableCell(using: PostOrThreadCellRegistration, for: indexPath, item: nrPost)
            }
        )
    }
}


//struct SmoothList_PReviews: PreviewProvider {
//    @State static var dim:DIMENSIONS = .shared
//    @State static var needsRefresh = false
//    @State static var needsScrollToTop = false
//    @State static var initialIndex:Int = 0
//    @State static var autoScroll = true
//    @State static var nrPosts = PreviewFetcher
//        .fetchEvents(NosturState.shared.followingPublicKeys, kind: 1)
//        .map {
//            $0.parentEvents = Event.getParentEvents($0)
//            return $0
//        }
//        .filter(onlyRootOrReplyingToFollower)
//        .compactMap { NRPost(event: $0) }
//
//    static var previews: some View {
//        VStack(spacing:0) {
//            SmoothList(needsRefresh: $needsRefresh, needsScrollToTop: $needsScrollToTop, initialIndex: $initialIndex, data: $nrPosts, autoScroll: $autoScroll, dim: dim)
//                .onAppear {
//                    needsRefresh = true
//                }
//        }
//        .withPreviewEnvironment()
//    }
//}

let thumbOptions = ImageRequest.ThumbnailOptions(size: CGSize(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_HEIGHT))

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
