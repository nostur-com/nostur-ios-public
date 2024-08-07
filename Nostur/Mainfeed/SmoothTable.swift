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
    var themes: Themes
    
    init(lvm: LVM, dim: DIMENSIONS, themes: Themes) {
        self.lvm = lvm
        self.dim = dim
        self.themes = themes
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
//        context.coordinator.data = lvm.posts
        
        // load posts
        refresh(cvh, coordinator: context.coordinator)
        
        // set up 'scroll to'- listener
        receiveNotification(.shouldScrollToFirstUnread)
            .sink { [weak coordinator = context.coordinator, weak cvh] _ in
                guard let cvh else { return }
                guard coordinator?.lvm.viewIsVisible ?? false else { return }
                guard cvh.tableView.numberOfRows(inSection: 0) > 0 else { return }
                guard context.coordinator.lvm.lvmCounter.count > 0 else {
                    // if no unread, scroll to top
                    if !context.coordinator.lvm.posts.value.isEmpty {
//                        cvh.tableView.layoutIfNeeded()
                        cvh.tableView.scrollToRow(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
//                        cvh.tableView.setNeedsLayout()
                    }
                    return
                }
                
                
                // last read index, or if nil, first index that is visible, minus 1
                let row = context.coordinator.lvm.lastReadIdIndex ?? ((cvh.tableView.indexPathsForVisibleRows?.first?.row ?? 0) - 1)
                let index = row-1
//                guard (cvh.dataSource?.snapshot().numberOfItems(inSection: .main) ?? 0) > index+1 else {
//                    L.og.error("🔴🔴 not scrolling: index+1: \(index+1) is > than cvh.dataSource?.snapshot().numberOfItems(inSection: .main)")
//                    return
//                }
                if index >= 0 && index < context.coordinator.lvm.posts.value.elements.count {
                    context.coordinator.lvm.lastReadId = context.coordinator.lvm.posts.value.elements[index].value.id
                }
                guard index >= 0, index < cvh.tableView.numberOfRows(inSection: 0) else { return }
                
                cvh.tableView.scrollToRow(at: IndexPath(item: max(0,index), section: 0), at: .top, animated: true)
            }
            .store(in: &context.coordinator.subscriptions)
        
        receiveNotification(.shouldScrollToTop)
            .sink { [weak coordinator = context.coordinator, weak cvh] _ in
                guard let cvh else { return }
                guard coordinator?.lvm.viewIsVisible ?? false else { return }
                guard cvh.tableView.numberOfRows(inSection: 0) > 0 else { return }
                if !(coordinator?.lvm.posts.value.isEmpty ?? true) {
                    cvh.tableView.scrollToRow(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
                }
            }
            .store(in: &context.coordinator.subscriptions)
    }
    
    private func makeViewHolder(parent viewController: UIViewControllerType,
                                          coordinator: Coordinator) -> ViewHolderType {
        L.sl.debug("⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): makeViewHolder")
        let viewHolder = TViewHolder(coordinator: coordinator) { uiView in
            
            viewController.view.addSubview(uiView)
            uiView.translatesAutoresizingMaskIntoConstraints = false
            uiView.backgroundColor = UIColor(themes.theme.listBackground) // UIColor(named: "ListBackground")
            
            
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
        L.sl.debug("⭐️ SmoothTable \(context.coordinator.lvm.id): OLD updateUIViewController \(context.coordinator.lvm.uuid)")
        L.sl.debug("⭐️ SmoothTable \(self.lvm.id): NEW updateUIViewController \(self.lvm.uuid)")
        
        if (lvm.uuid != context.coordinator.lvm.uuid) {
            // set up new
            if context.coordinator.viewHolder != nil {
                context.coordinator.initialApply = true
                configureView(context: context)
            }
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: Self.UIViewControllerType, coordinator: Self.Coordinator) {
        L.sl.debug("⭐️ SmoothTable. dismantleUIViewController \(coordinator.lvm.id) \(coordinator.lvm.pubkey?.short ?? "-")")
        coordinator.subscriptions.removeAll()
    }
    
    func refresh(_ viewHolder: TViewHolder, coordinator: Coordinator) {
        L.sl.debug("⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): refresh")
        if #available(iOS 16, *) {
            viewHolder.tableView.register(PostOrThreadCell16.self, forCellReuseIdentifier: "Nostur.PostOrThreadCell16")
        }
        else {
            viewHolder.tableView.register(PostOrThreadCell15.self, forCellReuseIdentifier: "Nostur.PostOrThreadCell15")
        }
        viewHolder.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
        viewHolder.dataSource = viewHolder.createDataSource(coordinator: coordinator)
        var snapshot = NSDiffableDataSourceSnapshot<SingleSection, String>()
        snapshot.appendSections([SingleSection.main])
        snapshot.appendItems(coordinator.lvm.posts.value.keys.elements, toSection: .main)
        viewHolder.dataSource?.apply(snapshot, animatingDifferences: false)
        
        
        coordinator.lvm.posts
            .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            .throttle(for: .seconds(2.5), scheduler: RunLoop.main, latest: true)
            .sink { [weak viewHolder, weak coordinator] data in
                guard let coordinator = coordinator, let viewHolder = viewHolder else { return }
                guard let dataSource = viewHolder.dataSource else { return }
                let currentNumberOfItems = dataSource.snapshot().numberOfItems(inSection: .main)
                let isInitialApply = coordinator.lvm.isInitialApply
                var snapshot = NSDiffableDataSourceSnapshot<SingleSection, String>()
                snapshot.appendSections([SingleSection.main])
                snapshot.appendItems(data.keys.elements, toSection: .main)
                
                let restoreToId: String? = viewHolder.tableView.contentOffset.y == 0
                    ? dataSource.snapshot().itemIdentifiers.first
                    : nil
                
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
                
                L.sl.debug("⭐️⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): \(currentNumberOfItems) → \(data.count)")
                
                if isInitialApply && data.count > 0 {
                    signpost(NRState.shared, "LAUNCH", .event, "SmoothTable: Applying snapshot")
                }
                dataSource.apply(snapshot, animatingDifferences: shouldAnimate) { [weak viewHolder, weak coordinator] in
                    guard let coordinator = coordinator, let viewHolder = viewHolder else { return }
                    if (isInitialApply) {
                        
                        // Scroll to initial position
                        // ON FIRST LOAD: SCROLL TO SOME INDEX (RESTORE)
                        if data.count > 0 {
                            signpost(NRState.shared, "LAUNCH", .end, "SmoothTable: snapshot applied")
                            coordinator.lvm.isInitialApply = false
                        }
                        if (coordinator.lvm.initialIndex > 4) && coordinator.lvm.initialIndex < viewHolder.tableView.numberOfRows(inSection: 0) {
                            L.sl.debug("⭐️⭐️⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): initial - scrollToItem: \(coordinator.lvm.initialIndex.description) posts: \(data.count)")
                            coordinator.lvm.isAtTop = false
                            viewHolder.tableView.scrollToRow(at: IndexPath(item: coordinator.lvm.initialIndex, section: 0), at: .top, animated: false)
                        }
                        else {
                            DispatchQueue.main.async {
                                if (viewHolder.tableView.contentOffset.y == 0) {
                                    coordinator.lvm.isAtTop = true
                                    // IF WE ARE AT TOP, ALWAYS SET COUNTER TO 0
                                    L.sl.debug("⭐️⭐️⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): Initial - posts: \(data.count) - force counter to 0")
                                    if coordinator.lvm.lvmCounter.count != 0 {
                                        coordinator.lvm.lvmCounter.count = 0
                                    }
                                    coordinator.lvm.lastReadId = data.keys.elements.first
                                }
                            }
                        }
                    }
                    else {
                        // KEEP POSITION AFTER INSERT, IF AUTOSCROLL IS DISABLED
                        if !SettingsStore.shared.autoScroll {
                            if let restoreToId, let restoreIndex = data.index(forKey: restoreToId), restoreIndex < viewHolder.tableView.numberOfRows(inSection: 0)  {
                                L.sl.debug("⭐️⭐️ SmoothTable \(coordinator.lvm.id) \(self.lvm.pubkey?.short ?? "-"): adding \(data.count - beforeCount) posts - scrollToItem: \(restoreIndex), restoreToId: \(restoreToId)")
//                                viewHolder.tableView.layoutIfNeeded()
                                viewHolder.tableView.scrollToRow(at: IndexPath(item: restoreIndex, section: 0), at: .top, animated: false)
//                                viewHolder.tableView.setNeedsLayout()
                            }
                        }
                    }
                    if shouldCommit {
                        CATransaction.commit()
                    }
                    coordinator.lvm.isInserting = false
                }
            }
            .store(in: &coordinator.subscriptions)
    }
    
    final class Coordinator: NSObject, UITableViewDelegate, UIScrollViewDelegate, UITableViewDataSourcePrefetching {
        public var subscriptions = Set<AnyCancellable>()
        public let parent: SmoothTable
        public var lvm: LVM
//        public var data:Posts = [:]
        public var viewHolder: ViewHolderType?
        private var scrollTimer: Timer?
        private var prefetcher:ImagePrefetcher
        private var prefetcherPFP:ImagePrefetcher
        
        private var lastCalledTimestamp: TimeInterval = 0
        private let debounceInterval: TimeInterval = 0.3 // Adjust this value to control the throttling
        
        public var initialApply = true
        
        public var dim: DIMENSIONS
        public var themes: Themes
        
        private let didScroll = PassthroughSubject<(Double, CGPoint), Never>() // contentOffset.y + .panGestureRecognizer.translation(in: scrollView)
        
        init(parent: SmoothTable) {
            self.parent = parent
            self.lvm = parent.lvm
            self.dim = parent.dim
            self.themes = parent.themes
            
            self.prefetcher = ImagePrefetcher(pipeline: ImageProcessing.shared.content)
            self.prefetcher.priority = .normal
            
            self.prefetcherPFP = ImagePrefetcher(pipeline: ImageProcessing.shared.pfp)
            self.prefetcherPFP.priority = .high
            
            super.init()
            handleScrolling()
        }
        
        func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
            let items = indexPaths.compactMap { lvm.posts.value.elements[safe: $0.row] }
            
            bg().perform { [weak self] in
                guard let self else { return }
                let imageWidth = parent.dim.availableNoteRowImageWidth()
                var imageRequests:[ImageRequest] = []
                var imageRequestsPFP:[ImageRequest] = []
                
                for (id, item) in items {
                    if !item.missingPs.isEmpty {
                        QueuedFetcher.shared.enqueue(pTags: item.missingPs)
                        L.fetching.debug("🟠🟠 Prefetcher: \(item.missingPs.count) missing contacts (event.pubkey or event.pTags) for: \(id)")
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
                                LinkPreviewCache.shared.cache.setObject(for: url, value: tags)
                                L.og.debug("✓✓ Loaded link preview meta tags from \(url)")
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
            let items = indexPaths.compactMap { lvm.posts.value.elements[safe: $0.row] }
            
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
            guard !lvm.isInserting else { return }
            if let lastAppearedId = lvm.posts.value.elements[safe: indexPath.row]?.value.id {
                lvm.lastAppearedIdSubject.send(lastAppearedId)
            }
        }
        
        public func handleScrolling() {
            // determine scroll direction
            if !IS_CATALYST {
                didScroll
                    .receive(on: DispatchQueue.main) // Not RunLoop.main because won't receive while scrolling
                    .debounce(for: .seconds(0.1), scheduler: DispatchQueue.main)
                    .sink { [weak self] (_, translation) in
                        guard let self = self else { return }
                        if !self.scrollDirectionDetermined {
                            if translation.y > 0 {
                                sendNotification(.scrollingUp)
                                self.scrollDirectionDetermined = true
                            }
                            else if translation.y < 0 {
                                sendNotification(.scrollingDown)
                                self.scrollDirectionDetermined = true
                            }
                        }
                    }
                    .store(in: &subscriptions)
            }
            
            // handle last appeared
            didScroll
                .receive(on: DispatchQueue.main) // Not RunLoop.main because won't receive while scrolling
                .throttle(for: .seconds(0.25), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] (contentOffsetY, _) in
                    guard let self = self else { return }
                    guard let indexPaths = self.viewHolder?.tableView.indexPathsForVisibleRows else {
                        return
                    }
                    let firstIndex = indexPaths.min(by: { $0.row < $1.row })
                    if contentOffsetY > 150 {
                        if self.lvm.isAtTop {
                            self.lvm.isAtTop = false
                        }
                    }
                    else {
                        self.lvm.isAtTop = true
                        
                        if let firstIndex, firstIndex.row < 1, self.lvm.lvmCounter.count != 0 {
                            self.lvm.lvmCounter.count = 0
                            L.og.debug("COUNTER: 0 - processScrollViewDidScroll")
                        }
                    }
                    
                    if let firstIndex, 
                       let lastAppearedId = self.lvm.posts.value.elements[safe: firstIndex.row]?.value.id,
                       !self.lvm.isInserting {
                            self.lvm.lastAppearedIdSubject.send(lastAppearedId)
                    }
                    self.lvm.postsAppearedSubject.send(
                        indexPaths.compactMap { [weak self] in
                            guard let self else { return nil }
                            return self.lvm.posts.value.elements[safe: $0.row]?.value.id
                        }
                    )
                }
                .store(in: &subscriptions)
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            didScroll.send(
                (scrollView.contentOffset.y, scrollView.panGestureRecognizer.translation(in: scrollView))
            )
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

final class PostOrThreadCell16: UITableViewCell {

    override func prepareForReuse() {
        super.prepareForReuse()

        contentConfiguration = nil
    }

    func configure(with nrPost: NRPost? = nil, dim: DIMENSIONS, themes: Themes) {
        if #available(iOS 16.0, *) {
            if let nrPost {
                return self.contentConfiguration = UIHostingConfiguration {
                    PostOrThread(nrPost: nrPost)
                        .environmentObject(dim) // Shouldn't need this, but otherwise sometimes crash? on iOS 16 but not 17
                        .environmentObject(themes) // Shouldn't need this, but otherwise sometimes crash? on iOS 16 but not 17
                }
                .margins(.all, 0)
            }
            
            return self.contentConfiguration = UIHostingConfiguration {
                Text("⚠️")
                    .environmentObject(dim) // Shouldn't need this, but otherwise sometimes crash? on iOS 16 but not 17
                    .environmentObject(themes) // Shouldn't need this, but otherwise sometimes crash? on iOS 16 but not 17
            }
            .margins(.all, 0)
        }
    }
}

final class PostOrThreadCell15: UITableViewCell {

    private var hostingController = UIHostingController<PostOrThread15?>(rootView: nil)
    
    override func prepareForReuse() {
        super.prepareForReuse()

        contentConfiguration = nil
    }

    func configure(with nrPost: NRPost? = nil, dim: DIMENSIONS, themes: Themes) {
        if let nrPost {
            // Fallback on earlier versions
            let view = PostOrThread15(nrPost: nrPost, themes: themes, dim: dim)
            
            self.hostingController.rootView = view
            self.hostingController.view.invalidateIntrinsicContentSize()
            
            contentView.addSubview(hostingController.view)
            
            hostingController.view
                           .translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.leadingAnchor.constraint(
                           equalTo: self.contentView.leadingAnchor
                       ).isActive = true
            hostingController.view.trailingAnchor.constraint(
                           equalTo: self.contentView.trailingAnchor
                       ).isActive = true
            hostingController.view.topAnchor.constraint(
                           equalTo: self.contentView.topAnchor
                       ).isActive = true
            hostingController.view.bottomAnchor.constraint(
                           equalTo: self.contentView.bottomAnchor
                       ).isActive = true
            
            return
        }
        
        return
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
        tableView.backgroundColor = UIColor.clear // This color flashes visible for a millisecond and is then covered by all other things
        tableView.allowsSelection = false
        tableView.delegate = coordinator
        tableView.prefetchDataSource = coordinator
        tableView.isPrefetchingEnabled = true
        if #available(iOS 16.0, *) {
            tableView.selfSizingInvalidation = .enabledIncludingConstraints
        }
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
                if #available(iOS 16, *) {
                    guard let cell = tableView.dequeueReusableCell(withIdentifier: PostOrThreadCell16.description(), for: indexPath) as? PostOrThreadCell16 else {
                        return UITableViewCell()
                    }
                    cell.configure(with: coordinator.lvm.posts.value.elements[safe: indexPath.row]?.value, dim: coordinator.dim, themes: coordinator.themes)
                    return cell
                }
                else {
                    guard let cell = tableView.dequeueReusableCell(withIdentifier: PostOrThreadCell15.description(), for: indexPath) as? PostOrThreadCell15 else {
                        return UITableViewCell()
                    }
                    cell.configure(with: coordinator.lvm.posts.value.elements[safe: indexPath.row]?.value, dim: coordinator.dim, themes: coordinator.themes)
                    return cell
                }
            }
        )
    }
}

enum SingleSection: CaseIterable {
    case main
}

func pfpImageRequestFor(_ pictureUrl:URL, size:CGFloat) -> ImageRequest {

    //    thumbOptions.createThumbnailFromImageAlways = true
    //    thumbOptions.shouldCacheImmediately = true
    let options: ImageRequest.Options = SettingsStore.shared.lowDataMode ? [.returnCacheDataDontLoad] : []

    if !SettingsStore.shared.animatedPFPenabled || pictureUrl.absoluteString.suffix(4) != ".gif" {
        return ImageRequest(url: pictureUrl,
                            //                            userInfo: [.thumbnailKey: thumbOptions],
                            processors: [
                                .resize(size: CGSize(width: size, height: size),
                                        unit: .points,
                                        contentMode: .aspectFill,
                                        crop: true,
                                        upscale: true)
                            ],
                            options: options,
                            userInfo: [.scaleKey: UIScreen.main.scale]
                            //                            userInfo: [.scaleKey: 1, .thumbnailKey: thumbOptions]
                            //                            userInfo: [.scaleKey: UIScreen.main.scale, .thumbnailKey: thumbOptions]
        )
    }
    return ImageRequest(url: pictureUrl)
}
