//
//  SnapshotTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/05/2023.
//

import SwiftUI
import UIKit
import Combine

struct SnapshotTest: View {
    
    let lvm:LVM
//    @State var vm = ViewModel()
    
    var body: some View {
        VStack {
//            Button("Add to top") {
//                vm.data.insert(UUID().uuidString, at: 0)
//            }
//            Button("Add to bottom") {
//                vm.data.append(UUID().uuidString)
//            }
            MyCollectionView(lvm: lvm)
//                .frame(width: 300, height: 500)
//                .fixedSize()
        }
    }
}

//class ViewModel: ObservableObject {
//    @Published var data = ["1","2","3"]
//}

struct SnapshotTest_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            if let p1 = PreviewFetcher.fetchNRPost(), let p2 = PreviewFetcher.fetchNRPost(), let p3 = PreviewFetcher.fetchNRPost() {
                let lvm = LVM(pubkeys: Set<String>(), listId: "Test")
                let _ = lvm.nrPostLeafs = [p1, p2, p3]
                SnapshotTest(lvm: lvm)
            }
        }
        .withPreviewEnvironment({ pe in pe.loadPosts() })
//            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}

enum SingleSectionT: CaseIterable {
    case main
}

public typealias NRID = String

struct MyCollectionView: UIViewControllerRepresentable {
    
//    private var vm:ViewModel
//
//    init(vm: ViewModel) {
//        self.vm = vm
//    }

        private var lvm:LVM
    
        init(lvm: LVM) {
            self.lvm = lvm
        }
    
    
    func makeUIViewController(context: Context) -> UICollectionViewController {
        
        // Set up collection view layout
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.showsSeparators = false
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
            section.contentInsets = .zero
            return section
        }
        layout.configuration.scrollDirection = .vertical
                
        // Setup collection view controller, set Coordinator as delegate
        let controller = UICollectionViewController(collectionViewLayout: layout)
        controller.collectionView.delegate = context.coordinator
        
 
        // Create data source, connect with CollectionView, store on Coordinator
        let dataSource = UICollectionViewDiffableDataSource<SingleSectionT, NRID>(collectionView: controller.collectionView) { collectionView, indexPath, itemIdentifier in
            print(indexPath.row)
            print(itemIdentifier)
            print(context.coordinator.data.count)
            return collectionView.dequeueConfiguredReusableCell(using: CellRegistration, for: indexPath, item: context.coordinator.data[indexPath.row])
        }
    
        // Load first data
        var snapshot = NSDiffableDataSourceSnapshot<SingleSectionT, NRID>()
        snapshot.appendSections([SingleSectionT.main])
        snapshot.appendItems(context.coordinator.ids, toSection: .main)
        dataSource.apply(snapshot)
        
        
        // Srote collectionView and dataSource on Coordinator
        context.coordinator.collectionView = controller.collectionView
        context.coordinator.dataSource = dataSource
        
        // Listen for data updates
        context.coordinator.listen()
        
        return controller
    }
    
    private var CellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, NRPost> = {
        .init { cell, indexPath, item in
            cell.contentConfiguration = UIHostingConfiguration {
                PostOrThread(nrPost: item)
//                    .background(Color.random)
//                    .hCentered()
            }
            .background(Color("ListBackground")) // Between and around every PostOrThread (NoteRows)
            .margins(.all, 0)
        }
    }()
    
    func updateUIViewController(_ uiViewController: UICollectionViewController, context: Context) {
    }
    
    typealias UIViewControllerType = UICollectionViewController
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, UICollectionViewDelegate, UIScrollViewDelegate {

        var dataSource:UICollectionViewDiffableDataSource<SingleSectionT, NRID>?
        var collectionView:UICollectionView?
        var lvm:LVM
        var data:[NRPost] = []
        var ids:[NRID] {
            data.map { $0.id }
        }
        var subscriptions = Set<AnyCancellable>()
        
        init(parent: MyCollectionView) {
            self.lvm = parent.lvm
        }
        
        func listen() {
            // create data source
            lvm.$nrPostLeafs
                .sink { [weak self] data in
                    guard let self = self else { return }
                    self.data = data
                    var snapshot = NSDiffableDataSourceSnapshot<SingleSectionT, NRID>()
                    snapshot.appendSections([SingleSectionT.main])
                    snapshot.appendItems(ids, toSection: .main)
                    self.dataSource?.apply(snapshot)
                }
                .store(in: &subscriptions)
        }
        
        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            if let lastAppearedId = data[safe: indexPath.row]?.id {
                lvm.lastAppearedIdSubject.send(lastAppearedId)
            }
        }
        
    }

}



final class SnapshotSource<SectionType: Hashable,ItemType: Hashable>: UICollectionViewDiffableDataSource<SectionType, ItemType> { }
