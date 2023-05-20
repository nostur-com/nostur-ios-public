//
//  SmoothList.swift Super smooth scrolling
//  Nostur
//
//  Created by Fabian Lachman on 11/04/2023.
//

import SwiftUI
import Nuke

let SMOOTHLIST_AUTOSCROLL_OFFSET = 3.0

enum SingleSection: CaseIterable {
    case main
}

struct SmoothList: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    typealias CollectionViewHolderType = CViewHolder
    typealias RowAppearedCallback = ((sectionIndex: Int, itemIndex: Int)) -> Void
    typealias FinishedScrollingCallback = ((isAtTop: Bool, indexPaths:[IndexPath])) -> Void
    
    @Binding var needsRefresh: Bool
    @Binding var needsFullReload: Bool
    @Binding var needsScrollToTop: Bool
    @Binding var needsScrollToIndex: Int?
    @Binding var data: [NRPost]
    @Binding var autoScroll: Bool
    @Binding var fullWidthImages: Bool
    var dim: DIMENSIONS
    private var onRowAppeared: RowAppearedCallback?
    private var onFinishedScrolling: FinishedScrollingCallback?
    
    init(needsRefresh: Binding<Bool>, needsFullReload:Binding<Bool>, needsScrollToTop:Binding<Bool>, needsScrollToIndex:Binding<Int?>, data: Binding<[NRPost]>, autoScroll: Binding<Bool>, fullWidthImages: Binding<Bool>, dim: DIMENSIONS, onRowAppeared: RowAppearedCallback? = nil, onFinishedScrolling: FinishedScrollingCallback? = nil) {
        self._needsRefresh = needsRefresh
        self._needsFullReload = needsFullReload
        self._needsScrollToTop = needsScrollToTop
        self._needsScrollToIndex = needsScrollToIndex
        self._data = data
        self._autoScroll = autoScroll
        self._fullWidthImages = fullWidthImages
        self.dim = dim
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
//        print("🔴🔴🔴🔴🔴🔴 updateUIViewController 🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if needsFullReload, let collectionViewHolder = context.coordinator.collectionViewHolder {
                print("🔴🔴🔴🔴🔴🔴 fullReload 🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴")
                fullReload(collectionViewHolder)
                Task {
                    needsFullReload = false
                }
            }
            
            if needsRefresh, let collectionViewHolder = context.coordinator.collectionViewHolder {
                print("🔴🔴🔴🔴🔴🔴 refreshData 🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴")
                refreshData(collectionViewHolder)
                Task {
                    needsRefresh = false
                }
            }
            
            if needsScrollToTop, let ch = context.coordinator.collectionViewHolder {
                print("🔴🔴🔴🔴🔴🔴 scrollToTop 🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴")
                // do the scroll
                ch.collectionView.setContentOffset(CGPoint(x:0, y: autoScroll ? 0 : SMOOTHLIST_AUTOSCROLL_OFFSET), animated: true)
                Task {
                    needsScrollToTop = false
                }
            }
            
            if needsScrollToIndex != nil, let ch = context.coordinator.collectionViewHolder {
                print("🔴🔴🔴🔴🔴🔴 scrollToIndex 🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴")
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
    
    private func fullReload(_ collectionViewHolder: CollectionViewHolderType) {
        collectionViewHolder.collectionView.reloadData()
    }
    private func refreshData(_ collectionViewHolder: CollectionViewHolderType) {
        var newSnapshot = NSDiffableDataSourceSnapshot<SingleSection, String>()
        newSnapshot.appendSections([SingleSection.main])
        newSnapshot.appendItems(data.map { $0.id }, toSection: SingleSection.main)
        
        let isInitialApply = collectionViewHolder.dataSource.snapshot().sectionIdentifiers.isEmpty
        
        collectionViewHolder.dataSource.apply(newSnapshot, animatingDifferences: !isInitialApply) {
            if (isInitialApply) { // Scroll to initial position
                DispatchQueue.main.async {
                    if (self.needsScrollToIndex != nil) && (self.needsScrollToIndex! > 4) {
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
    
    final class Coordinator: NSObject, UICollectionViewDelegate, UIScrollViewDelegate, UICollectionViewDataSourcePrefetching, UICollectionViewDelegateFlowLayout { //, UICollectionViewDataSource {
        let parent: SmoothList
        var collectionViewHolder: CollectionViewHolderType?
        var scrollTimer: Timer?
        var prefetcher:ImagePrefetcher
        var prefetcherPFP:ImagePrefetcher
//        var prefetcherPFPnotFollowing:ImagePrefetcher
        
        private var lastCalledTimestamp: TimeInterval = 0
        private let debounceInterval: TimeInterval = 0.3 // Adjust this value to control the throttling
        
        
        init(parent: SmoothList) {
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
                guard let item = parent.data[safe: indexPath.row] else { continue }
                
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
                    .filter{ $0.contact?.following ?? false }
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
                guard let item = parent.data[safe: indexPath.row] else { continue }
                
                if item.missingPs.count > 0 {
                    QueuedFetcher.shared.dequeue(pTags: item.missingPs)
                }
                
                if let picture = item.contact?.pictureUrl, picture.prefix(7) != "http://" {
                    imageRequestsPFP.append(pfpImageRequestFor(picture))
                }
                
                imageRequestsPFP.append(contentsOf: item
                    .parentPosts
                    .filter{ $0.contact?.following ?? false }
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
            // Calculate the time since the last call
            let currentTime = Date().timeIntervalSince1970
            let timeSinceLastCall = currentTime - lastCalledTimestamp
            
            // Check if the debounceInterval has passed
            if timeSinceLastCall > debounceInterval {
                // Update the lastCalledTimestamp
                lastCalledTimestamp = currentTime
                
                // Your throttled code here
                parent.onRowAppeared?((sectionIndex: indexPath.section, itemIndex: indexPath.row))
            }
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
                //                print("IS AT TOP FALSE")
                parent.onFinishedScrolling?((isAtTop:false, indexPaths:indexPaths)) // didFinish and isAtTop=false
                
            }
            else {
                //                print("IS AT TOP TRUE")
                parent.onFinishedScrolling?((isAtTop:true, indexPaths:indexPaths)) // didFinish and isAtTop=true
                
                if (!parent.autoScroll) && (scrollView.contentOffset.y < SMOOTHLIST_AUTOSCROLL_OFFSET) {
                    // if really at top, push back a little, so new items inserted at top don't push all down
                    //                    scrollView.layoutIfNeeded();
                    scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: SMOOTHLIST_AUTOSCROLL_OFFSET), animated: true)
                }
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
    private(set) lazy var dataSource: DataSourceType = createDataSource()
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
                    .boxShadow()
                    .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING)
                    .padding(.vertical, 10)
                //                    .frame(maxWidth: .infinity)
            }
            .background(Color("ListBackground")) // Between and around every PostOrThread (NoteRows)
            .margins(.all, 0)
            //            cell.layer.shouldRasterize = true
            //            cell.layer.rasterizationScale = UIScreen.main.scale
        }
    }()
    
    private var FullWidthPostOrThreadCellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, NRPost> = {
        .init { cell, indexPath, nrPost in
            cell.contentConfiguration = UIHostingConfiguration {
                PostOrThread(nrPost: nrPost, fullWidth: true)
                    .boxShadow()
                    .padding(.vertical, 10)
            }
            .background(Color("ListBackground")) // Between and around every PostOrThread (NoteRows)
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
            .background(Color("ListBackground")) // Between and around every PostOrThread (NoteRows)
            .margins(.all, 0)
        }
    }()
    
    private func createDataSource() -> DataSourceType {
        DataSourcy<SingleSection, String>(
            collectionView: collectionView,
            cellProvider: { [weak self] collectionView, indexPath, identifier -> UICollectionViewCell? in
                guard let self = self else { return nil }
                
                guard let nrPost = self.coordinator?.parent.data.first(where: { $0.id == identifier }) else {
                    return self.collectionView.dequeueConfiguredReusableCell(using: MissingCellRegistration, for: indexPath, item: "🧨")
                }
                
                if self.coordinator?.parent.fullWidthImages ?? false {
                    return self.collectionView.dequeueConfiguredReusableCell(using: FullWidthPostOrThreadCellRegistration, for: indexPath, item: nrPost)
                }
                return self.collectionView.dequeueConfiguredReusableCell(using: PostOrThreadCellRegistration, for: indexPath, item: nrPost)
            }
        )
    }
}


struct SmoothList_PReviews: PreviewProvider {
    @State static var dim:DIMENSIONS = .shared
    @State static var needsRefresh = false
    @State static var needsFullReload = false
    @State static var needsScrollToTop = false
    @State static var needsScrollToIndex:Int? = nil
    @State static var autoScroll = true
    @State static var fullWidthImages = true
    @State static var nrPosts = PreviewFetcher
        .fetchEvents(NosturState.shared.followingPublicKeys, kind: 1)
        .map {
            $0.parentEvents = Event.getParentEvents($0)
            return $0
        }
        .filter(onlyRootOrReplyingToFollower)
        .compactMap { NRPost(event: $0) }
    
    static var previews: some View {
        VStack(spacing:0) {
            SmoothList(needsRefresh: $needsRefresh, needsFullReload: $needsFullReload, needsScrollToTop: $needsScrollToTop, needsScrollToIndex: $needsScrollToIndex, data: $nrPosts, autoScroll: $autoScroll, fullWidthImages: $fullWidthImages, dim: dim)
                .onAppear {
                    needsRefresh = true
                }
        }
        .withPreviewEnvironment()
    }
}


func pfpImageRequestFor(_ picture:String) -> ImageRequest {
    if !SettingsStore.shared.animatedPFPenabled || picture.suffix(4) != ".gif" {
        return ImageRequest(url: URL(string:picture),
                            processors: [.resize(size: CGSize(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_HEIGHT), unit: .points, contentMode: .aspectFill, crop: true, upscale: true)],
                            userInfo: [.scaleKey: UIScreen.main.scale])
    }
    return ImageRequest(url: URL(string:picture))
}
