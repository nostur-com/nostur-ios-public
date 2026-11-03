//
//  SideTabs.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/09/2025.
//

import SwiftUI

struct SideTabs: View {
    @EnvironmentObject private var dm: DMsVM
    @Environment(\.showSidebar) @Binding var showSidebar: Bool
    @Environment(\.theme) private var theme
    @ObservedObject var vm: MacColumnsVM
    @Binding var selectedTab: String
    @State private var unread: Int = 0
    
    var body: some View {
        VStack(alignment: .center) {
            if let account = account() {
                PFP(pubkey: account.publicKey, account: account, size: 30)
                    .padding(10)
                    .onTapGesture {
                        showSidebar = true
                    }
            }
            
            Group {
                
                Button("Following", systemImage: "house") {
                    selectedTab = "Main"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Main" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Notifications", systemImage: "bell") {
                    selectedTab = "Notifications"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Notifications" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                .badgeCompat(unread)
                
                Button("Search", systemImage: "magnifyingglass") {
                    selectedTab = "Search"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Search" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Bookmarks", systemImage: "bookmark") {
                    selectedTab = "Bookmarks"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Bookmarks" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Messages", systemImage: "envelope") {
                    selectedTab = "Messages"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Messages" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                .badgeCompat((dm.unread + dm.unreadNewRequestsCount))
            
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 20))
            .foregroundColor(theme.accent)
            
            Spacer()
            
            
            Group {
                if IS_IPHONE {
                    Toggle(isOn: Binding(
                        get: { vm.duoColumnCount == 3 },
                        set: { vm.setDuoColumnCount($0 ? 3 : 2) }
                    )) {
                        Label("Three columns", systemImage: vm.duoColumnCount == 3 ? "rectangle.split.3x1" : "rectangle.split.2x1")
                    }
                    .toggleStyle(.button)
                    .accessibilityValue(Text("\(vm.duoColumnCount) columns"))
                    .help("Toggle two or three columns")
                }
                else {
                    Button {
                        withAnimation {
                            vm.addColumn()
                        }
                    } label: {
                        Image(systemName: "rectangle.stack.badge.plus")
                    }
                    .help("Add column")
                    .disabled(!vm.allowAddColumn)
                    Color.clear.frame(height: 5)
                    Button {
                        withAnimation {
                            vm.removeColumn()
                        }
                    } label: {
                        Image(systemName: "rectangle.stack.badge.minus")
                    }
                    .help("Remove column")
                    .disabled(!vm.allowRemoveColumn)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 20))
            .foregroundColor(theme.accent)
            
            Spacer()
            
            Button { AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .textNote) } label: {
                Image(systemName: "square.and.pencil.circle.fill")
            }
            .help("New Post")
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 34))
            .foregroundColor(theme.accent)
            .padding(.bottom, 20)
        }
//        .padding(.top, 100)
        
        .onReceive(NotificationsViewModel.shared.unreadPublisher) { unread in
            if unread != self.unread {
                self.unread = unread
            }
        }
    }
}

/// Place the app rail in the system-provided bar region without making the
/// feed columns descendants of another navigation stack.
@available(iOS 27.1, *)
struct DuoProNavigation: ViewModifier {
    @ObservedObject var vm: MacColumnsVM
    @Environment(\.showSidebar) private var showSidebar
    @Environment(\.theme) private var theme

    @State private var hasVerticalBar = true

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .leading, spacing: hasVerticalBar ? 0 : COLUMN_SPACING) {
                if !hasVerticalBar {
                    SideTabs(vm: vm, selectedTab: $vm.selectedTab).frame(width: SIDEBAR_WIDTH)
                }
            }
            .overlay {
                DuoProRailHost(vm: vm, showSidebar: showSidebar, theme: theme) { hasVerticalBar = $0 }
                    .ignoresSafeArea(.container, edges: .all)
            }
    }
}

@available(iOS 27.1, *)
private struct DuoProRailHost: UIViewControllerRepresentable {
    @ObservedObject var vm: MacColumnsVM
    @Binding var showSidebar: Bool
    let theme: Theme
    var onVerticalBarChange: (Bool) -> Void

    private var rail: AnyView {
        AnyView(SideTabs(vm: vm, selectedTab: $vm.selectedTab)
            .frame(width: SIDEBAR_WIDTH)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(DMsVM.shared)
            .environment(\.showSidebar, $showSidebar)
            .environment(\.theme, theme))
    }

    func makeUIViewController(context: Context) -> DuoProRailController {
        let controller = DuoProRailController(rail: rail)
        controller.onVerticalBarChange = onVerticalBarChange
        return controller
    }

    func updateUIViewController(_ controller: DuoProRailController, context: Context) {
        controller.onVerticalBarChange = onVerticalBarChange
        controller.host.rootView = rail
        controller.view.setNeedsLayout()
    }
}

@available(iOS 27.1, *)
final class DuoProRailController: UIViewController {
    let host: UIHostingController<AnyView>
    var onVerticalBarChange: ((Bool) -> Void)?
    private var reportedBarState: Bool?
    private var regionConstraints: [NSLayoutConstraint] = []
    private var regionEdge: UIRectEdge?
    private var regionExtent: CGFloat = -1

    init(rail: AnyView) {
        host = UIHostingController(rootView: rail)
        super.init(nibName: nil, bundle: nil)
        // The bar layout region already excludes system controls and corners.
        host.safeAreaRegions = []
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = ProRailPassthroughView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let hasBar = view.traitCollection.verticalBarEdge != .unspecified
        host.view.isHidden = !hasBar
        if reportedBarState != hasBar {
            reportedBarState = hasBar
            DispatchQueue.main.async { [weak self] in
                guard let self, self.reportedBarState == hasBar else { return }
                self.onVerticalBarChange?(hasBar)
            }
        }
        guard hasBar else { return }
        let isRTL = view.traitCollection.layoutDirection == .rightToLeft
        let edge: UIRectEdge
        switch view.traitCollection.verticalBarEdge {
        case .leading: edge = isRTL ? .right : .left
        case .trailing: edge = isRTL ? .left : .right
        default: edge = .right
        }
        // Extent is the control width. The system adds its own edge clearance.
        let extent = SIDEBAR_WIDTH
        guard regionEdge != edge || regionExtent != extent else { return }
        regionEdge = edge
        regionExtent = extent
        NSLayoutConstraint.deactivate(regionConstraints)
        let guide = view.layoutGuide(for: .bar(onEdge: edge, extent: extent))
        regionConstraints = [host.view.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                             host.view.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
                             host.view.topAnchor.constraint(equalTo: guide.topAnchor),
                             host.view.bottomAnchor.constraint(equalTo: guide.bottomAnchor)]
        NSLayoutConstraint.activate(regionConstraints)
    }
}

private final class ProRailPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
