//
//  SmoothTable.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/12/2023.
//
import SwiftUI
import Nuke
import Combine

// The main feed
// It's a UITableView in a UIViewControllerRepresentable because
// plain SwiftUI ScrollView/LazyVStacks doesn't give smooth scrolling
// and is lacking features to load new posts at top while maintaining
// scroll position

// COPY PASTA FROM SmoothList, which is the same but with UICollectionView instead of UITableView

struct SmoothTable: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    typealias ViewHolderType = TViewHolder
    
    var dim: DIMENSIONS
    var lvm: LVM
    var theme: Theme
    
    init(lvm:LVM, dim:DIMENSIONS, theme:Theme) {
        self.lvm = lvm
        self.dim = dim
        self.theme = theme
    }
    
    func makeCoordinator() -> Coordinator {
        L.sl.debug("⭐️ SmoothTable \(self.lvm.id) \(self.lvm.pubkey?.short ?? "-"): makeCoordinator")
        return Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> UIViewControllerType {
        L.sl.debug("⭐️ SmoothTable \(context.coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): makeUIViewController")
        let viewController = UIViewControllerType()
        let viewHolder = makeViewHolder(parent: viewController, coordinator:context.coordinator)
        context.coordinator.viewHolder = viewHolder
        
        if context.coordinator.viewHolder != nil {
            configureView(context: context)
        }
        return viewController
    }
    
    private func configureView(context: Context) {
        guard let cvh = context.coordinator.viewHolder else { return }
        
        // configure lvm
        context.coordinator.lvm = lvm
        context.coordinator.data = lvm.posts
        
        // load posts
        refresh(cvh, coordinator: context.coordinator)
        
        // set up 'scroll to'- listener
        receiveNotification(.shouldScrollToFirstUnread)
            .sink { _ in
                guard context.coordinator.lvm.viewIsVisible else { return }
                guard context.coordinator.lvm.lvmCounter.count > 0 else {
                    // if no unread, scroll to top
                    if !context.coordinator.lvm.posts.isEmpty {
//                        cvh.tableView.layoutIfNeeded()
                        cvh.tableView.scrollToRow(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
//                        cvh.tableView.setNeedsLayout()
                    }
                    return
                }
                
                
                // last read index, or if nil, first index that is visible, minus 1
                let row = context.coordinator.lvm.lastReadIdIndex ?? ((cvh.tableView.indexPathsForVisibleRows?.first?.row ?? 0) - 1)
                let index = row-1
                guard (cvh.dataSource?.snapshot().numberOfItems(inSection: .main) ?? 0) > index+1 else {
                    L.og.error("🔴🔴 not scrolling: index+1: \(index+1) is > than cvh.dataSource?.snapshot().numberOfItems(inSection: .main)")
                    return
                }
                if index >= 0 && index < context.coordinator.lvm.posts.elements.count {
                    context.coordinator.lvm.lastReadId = context.coordinator.lvm.posts.elements[index].value.id
                }
//                cvh.tableView.layoutIfNeeded()
                cvh.tableView.scrollToRow(at: IndexPath(item: max(0,index), section: 0), at: .top, animated: true)
//                cvh.tableView.setNeedsLayout()
            }
            .store(in: &context.coordinator.subscriptions)
        
        receiveNotification(.shouldScrollToTop)
            .sink { _ in
                guard context.coordinator.lvm.viewIsVisible else { return }
                if !context.coordinator.lvm.posts.isEmpty {
//                    cvh.tableView.layoutIfNeeded()
                    cvh.tableView.scrollToRow(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
//                    cvh.tableView.setNeedsLayout()
                }
            }
            .store(in: &context.coordinator.subscriptions)
    }
    
    private func makeViewHolder(parent viewController: UIViewControllerType,
                                          coordinator: Coordinator) -> ViewHolderType {
        L.sl.info("⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): makeViewHolder")
        let viewHolder = TViewHolder(coordinator: coordinator) { uiView in
            //            uiCollectionView.translatesAutoresizingMaskIntoConstraints = false
            uiView.translatesAutoresizingMaskIntoConstraints = false
            uiView.backgroundColor = UIColor(theme.listBackground) // UIColor(named: "ListBackground")
            viewController.view.addSubview(uiView)
            
            NSLayoutConstraint.activate([
                viewController.view.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
                viewController.view.topAnchor.constraint(equalTo: uiView.topAnchor), // Add this line
                viewController.view.bottomAnchor.constraint(equalTo: uiView.bottomAnchor)
            ])
        }
        return viewHolder
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        L.sl.info("⭐️ SmoothTable \(context.coordinator.lvm.id): OLD updateUIViewController \(context.coordinator.lvm.uuid)")
        L.sl.info("⭐️ SmoothTable \(self.lvm.id): NEW updateUIViewController \(self.lvm.uuid)")
        
        if (lvm.uuid != context.coordinator.lvm.uuid) {
            // set up new
            if context.coordinator.viewHolder != nil {
                configureView(context: context)
            }
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: Self.UIViewControllerType, coordinator: Self.Coordinator) {
        L.sl.debug("⭐️ SmoothTable. dismantleUIViewController \(coordinator.lvm.id) \(coordinator.lvm.pubkey?.short ?? "-")")
        coordinator.subscriptions.removeAll()
    }
    
    func refresh(_ viewHolder:TViewHolder, coordinator:Coordinator) {
        L.sl.info("⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): refresh")
        coordinator.subscriptions.removeAll()
        viewHolder.tableView.register(PostOrThreadCell.self, forCellReuseIdentifier: "Nostur.PostOrThreadCell")
        viewHolder.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
        viewHolder.dataSource = viewHolder.createDataSource(coordinator: coordinator)
        var snapshot = NSDiffableDataSourceSnapshot<SingleSection, String>()
        snapshot.appendSections([SingleSection.main])
        snapshot.appendItems(coordinator.data.keys.elements, toSection: .main)
        viewHolder.dataSource?.apply(snapshot, animatingDifferences: false)
        
        
        coordinator.lvm.$posts
        //            .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
        //            .throttle(for: .seconds(2.5), scheduler: RunLoop.main, latest: true)
            .sink { data in
                coordinator.data = data
                guard let dataSource = viewHolder.dataSource else { return }
                let currentNumberOfItems = dataSource.snapshot().numberOfItems(inSection: .main)
                let isInitialApply = coordinator.initialApply
                var snapshot = NSDiffableDataSourceSnapshot<SingleSection, String>()
                snapshot.appendSections([SingleSection.main])
                snapshot.appendItems(data.keys.elements, toSection: .main)
                
                let restoreToId:String? = viewHolder.tableView.contentOffset.y == 0 ?
                dataSource.snapshot().itemIdentifiers.first : nil
                
                var shouldCommit = false
                if !SettingsStore.shared.autoScroll && restoreToId != nil {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    shouldCommit = true
                }
                
                // Never animate on the first load (!isInitialApply)
                // Then only animate if we don't restore to top (restoreTopId == nil)
                // or if we have auto scroll enabled (SettingsStore.shared.autoScroll)
                let shouldAnimate = !isInitialApply && (restoreToId == nil || SettingsStore.shared.autoScroll)
                
                let beforeCount = !isInitialApply ? currentNumberOfItems : 0
                
                L.sl.info("⭐️⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): \(currentNumberOfItems) → \(data.count)")
                
                if isInitialApply && data.count > 0 {
                    signpost(NRState.shared, "LAUNCH", .event, "SmoothTable: Applying snapshot")
                }
                dataSource.apply(snapshot, animatingDifferences: shouldAnimate) {
                    if (isInitialApply) {
                        coordinator.initialApply = false
                        // Scroll to initial position
                        //                        // ON FIRST LOAD: SCROLL TO SOME INDEX (RESTORE)
                        //                        if data.count > 0 {
                        //                            signpost(NRState.shared, "LAUNCH", .end, "SmoothTable: snapshot applied")
                        //                        }
                        //                        if (coordinator.lvm.initialIndex > 4) {
                        //                            L.sl.info("⭐️⭐️⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): initial - scrollToItem: \(coordinator.lvm.initialIndex.description) posts: \(data.count)")
                        //                            coordinator.lvm.isAtTop = false
                        //                            viewHolder.tableView.scrollToItem(at: IndexPath(item: coordinator.lvm.initialIndex, section: 0), at: .top, animated: false)
                        //                        }
                        //                        else if (viewHolder.tableView.contentOffset.y == 0) {
                        //                            // IF WE ARE AT TOP, ALWAYS SET COUNTER TO 0
                        ////                            L.sl.info("⭐️⭐️⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): Initial - posts: \(data.count) - force counter to 0")
                        ////                            coordinator.lvm.lvmCounter.count = 0 // Publishing changes from within view updates is not allowed, this will cause undefined behavior.
                        //                            coordinator.lvm.lastReadId = coordinator.lvm.posts.keys.elements.first
                        //
                        //                            DispatchQueue.main.async {
                        //                                // IF WE ARE AT TOP, ALWAYS SET COUNTER TO 0
                        //                                L.sl.info("⭐️⭐️⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): Initial - posts: \(data.count) - force counter to 0")
                        //                                coordinator.lvm.lvmCounter.count = 0 // Publishing changes from within view updates is not allowed, this will cause undefined behavior.
                        //                                coordinator.lvm.lastReadId = coordinator.lvm.posts.keys.elements.first
                        //                            }
                        //                        }
                    }
                    else {
                        // KEEP POSITION AFTER INSERT, IF AUTOSCROLL IS DISABLED
                        if !SettingsStore.shared.autoScroll {
                            if let restoreToId, let restoreIndex = snapshot.itemIdentifiers(inSection: .main).firstIndex(of: restoreToId) { // data.index(forKey: restoreToId) is wrong?
                                L.sl.info("⭐️⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): adding \(data.count - beforeCount) posts - scrollToItem: \(restoreIndex), restoreToId: \(restoreToId)")
//                                viewHolder.tableView.layoutIfNeeded()
                                viewHolder.tableView.scrollToRow(at: IndexPath(item: restoreIndex, section: 0), at: .top, animated: false)
//                                viewHolder.tableView.setNeedsLayout()
                            }
                        }
                    }
                    if shouldCommit {
                        CATransaction.commit()
                    }
                }
            }
            .store(in: &coordinator.subscriptions)
    }
    
    final class Coordinator: NSObject, UITableViewDelegate, UIScrollViewDelegate, UITableViewDataSourcePrefetching {
        public var subscriptions = Set<AnyCancellable>()
        public let parent: SmoothTable
        public var lvm: LVM
        public var data:Posts = [:]
        public var viewHolder: ViewHolderType?
        private var scrollTimer: Timer?
        private var prefetcher:ImagePrefetcher
        private var prefetcherPFP:ImagePrefetcher
        
        private var lastCalledTimestamp: TimeInterval = 0
        private let debounceInterval: TimeInterval = 0.3 // Adjust this value to control the throttling
        
        public var initialApply = true
        
        init(parent: SmoothTable) {
            self.parent = parent
            self.lvm = parent.lvm
            
            self.prefetcher = ImagePrefetcher(pipeline: ImageProcessing.shared.content)
            self.prefetcher.priority = .normal
            
            self.prefetcherPFP = ImagePrefetcher(pipeline: ImageProcessing.shared.pfp)
            self.prefetcherPFP.priority = .high
        }
        
        func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
            let items = indexPaths.compactMap { data.elements[safe: $0.row] }
            
            bg().perform { [weak self] in
                guard let self else { return }
                let imageWidth = parent.dim.availableNoteRowImageWidth()
                var imageRequests:[ImageRequest] = []
                var imageRequestsPFP:[ImageRequest] = []
                
                for (id, item) in items {
                    if !item.missingPs.isEmpty {
                        QueuedFetcher.shared.enqueue(pTags: item.missingPs)
                        L.fetching.info("🟠🟠 Prefetcher: \(item.missingPs.count) missing contacts (event.pubkey or event.pTags) for: \(id)")
                    }
                    
                    // Everything below here is image or link preview fetching, skip if low data mode
                    guard !SettingsStore.shared.lowDataMode else { continue }
                    
                    if let pictureUrl = item.contact?.pictureUrl, pictureUrl.absoluteString.prefix(7) != "http://" {
                        imageRequestsPFP.append(pfpImageRequestFor(pictureUrl, size: DIMENSIONS.POST_ROW_PFP_DIAMETER))
                    }
                    
                    imageRequestsPFP.append(contentsOf: item
                        .parentPosts
                        .compactMap { $0.contact?.pictureUrl }
                        .filter { $0.absoluteString.prefix(7) != "http://" }
                        .map { pfpImageRequestFor($0, size: DIMENSIONS.POST_ROW_PFP_DIAMETER) }
                    )
                    
                    for element in item.contentElements {
                        switch element {
                        case .image(let mediaContent):
                            if mediaContent.url.absoluteString.prefix(7) == "http://" { continue }
                            // SHOULD BE SAME AS IN ContentRenderer:
                            if let dimensions = mediaContent.dimensions {
                                let scaledDimensions = Nostur.scaledToFit(dimensions, scale: UIScreen.main.scale, maxWidth: dimensions.width, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                                
                                // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                                imageRequests.append(makeImageRequest(mediaContent.url, width: scaledDimensions.width, height: scaledDimensions.height, label: "prefetch"))
                            }
                            else {
                                // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                                imageRequests.append(makeImageRequest(mediaContent.url, width: imageWidth, height: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, label: "prefetch (unscaled)"))
                            }
                        default:
                            continue
                        }
                    }
                    
                    // TODO: do parent posts if replies is enabled (PostOrThread)
                    //                for parentPost in item.parentPosts {
                    //                    // Same as above
                    //                    // for element in parentPost.contentElements { }
                    //                }
                    
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
                
                guard !SettingsStore.shared.lowDataMode else { return }
                if !imageRequests.isEmpty {
                    prefetcher.startPrefetching(with: imageRequests)
                }
                if !imageRequestsPFP.isEmpty {
                    prefetcherPFP.startPrefetching(with: imageRequestsPFP)
                }
            }
        }
        
        func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
            let items = indexPaths.compactMap { data.elements[safe: $0.row] }
            
            bg().perform { [weak self] in
                guard let self else { return }
                let imageWidth = parent.dim.availableNoteRowImageWidth()
                var imageRequests:[ImageRequest] = []
                var imageRequestsPFP:[ImageRequest] = []
                
                for (_, item) in items {
                    
                    if !item.missingPs.isEmpty {
                        QueuedFetcher.shared.dequeue(pTags: item.missingPs)
                    }
                    
                    // Everything below here is image or link preview fetching, skip if low data mode
                    guard !SettingsStore.shared.lowDataMode else { continue }
                    
                    if let pictureUrl = item.contact?.pictureUrl, pictureUrl.absoluteString.prefix(7) != "http://" {
                        imageRequestsPFP.append(pfpImageRequestFor(pictureUrl, size: DIMENSIONS.POST_ROW_PFP_DIAMETER))
                    }
                    
                    imageRequestsPFP.append(contentsOf: item
                        .parentPosts
                        .compactMap { $0.contact?.pictureUrl }
                        .filter { $0.absoluteString.prefix(7) != "http://" }
                        .map { pfpImageRequestFor($0, size: DIMENSIONS.POST_ROW_PFP_DIAMETER) }
                    )
                    
                    for element in item.contentElements {
                        switch element {
                        case .image(let mediaContent):
                            if mediaContent.url.absoluteString.prefix(7) == "http://" { continue }
                            // SHOULD BE SAME AS IN ContentRenderer:
                            if let dimensions = mediaContent.dimensions {
                                let scaledDimensions = Nostur.scaledToFit(dimensions, scale: UIScreen.main.scale, maxWidth: dimensions.width, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                                
                                
                                // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                                imageRequests.append(makeImageRequest(mediaContent.url, width: scaledDimensions.width, height: scaledDimensions.height, label: "cancel prefetch"))
                            }
                            else {
                                // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                                imageRequests.append(makeImageRequest(mediaContent.url, width: imageWidth, height: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, label: "cancel prefetch (unscaled)"))
                            }
                        default:
                            continue
                        }
                    }
                    
                    // TODO: do parent posts if replies is enabled (PostOrThread)
                    //                for parentPost in item.parentPosts {
                    //                    // Same as above
                    //                    // for element in parentPost.contentElements { }
                    //                }
                }
                
                guard !SettingsStore.shared.lowDataMode else { return }
                if (!imageRequests.isEmpty) {
                    prefetcher.stopPrefetching(with: imageRequests)
                }
                if !imageRequestsPFP.isEmpty {
                    prefetcherPFP.stopPrefetching(with: imageRequestsPFP)
                }
            }
        }
        
        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            if let lastAppearedId = data.elements[safe: indexPath.row]?.value.id {
                lvm.lastAppearedIdSubject.send(lastAppearedId)
            }
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
            guard let indexPaths = viewHolder?.tableView.indexPathsForVisibleRows else {
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
                        L.og.debug("COUNTER: 0 - processScrollViewDidScroll")
                    }
                    
                    if let lastAppearedId = data.elements[safe: firstIndex.row]?.value.id {
                        lvm.lastAppearedIdSubject.send(lastAppearedId)
                    }
                }
            }
            
            lvm.postsAppearedSubject.send(indexPaths.compactMap { data.elements[safe: $0.row]?.value.id })
        }
        
        private var scrollDirectionDetermined = false
        
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            scrollDirectionDetermined = false
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            scrollDirectionDetermined = false
        }
    }
}

final class PostOrThreadCell: UITableViewCell {

    override func prepareForReuse() {
        super.prepareForReuse()

        contentConfiguration = nil
    }

    func configure(with nrPost: NRPost) {
        self.contentConfiguration = UIHostingConfiguration {
            PostOrThread(nrPost: nrPost)
        }
        .margins(.all, 0)
    }
}


final class TViewHolder {
    let tableView: UITableView
    typealias DataSourceType = UITableViewDiffableDataSource<SingleSection, String>
    var dataSource: DataSourceType?
    private let coordinator: SmoothTable.Coordinator?
    
    init(
        coordinator: SmoothTable.Coordinator,
        onInitialized: @escaping (UITableView) -> Void
    ) {
        self.coordinator = coordinator
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.backgroundColor = UIColor.clear // This color flashes visible for a milisecond and is then covered by all other things
        tableView.allowsSelection = false
        tableView.delegate = coordinator
        tableView.prefetchDataSource = coordinator
        tableView.isPrefetchingEnabled = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.selfSizingInvalidation = .enabledIncludingConstraints
        //        tableView.selfSizingInvalidation = .enabled
        tableView.isOpaque = true
        tableView.dragInteractionEnabled = false
        tableView.allowsSelection = false
        tableView.allowsFocus = false
        onInitialized(tableView)
    }
    
    func createDataSource(coordinator: SmoothTable.Coordinator) -> DataSourceType {
        L.sl.debug("⭐️ SmoothTable \(coordinator.lvm.id) \(coordinator.lvm.pubkey?.short ?? "-"): TViewHolder.createDataSource")
        return UITableViewDiffableDataSource<SingleSection, String>(
            tableView: tableView,
            cellProvider: { tableView, indexPath, identifier -> UITableViewCell? in
                guard let cell = tableView.dequeueReusableCell(withIdentifier: PostOrThreadCell.description(), for: indexPath) as? PostOrThreadCell else {
                    return UITableViewCell()
                }
                cell.configure(with: coordinator.data.elements[indexPath.row].value)
                return cell
            }
        )
    }
}
