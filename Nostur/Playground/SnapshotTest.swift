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
import Nuke
import NukeVideo

struct SnapshotTest_Previews: PreviewProvider {
    static var previews: some View {
        
        // Use ImageDecoderRegistory to add the decoder to the
        let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
        
        PreviewContainer({ pe in
            pe.parseMessages([
                ###"["EVENT","3bca337a-8db2-45ca-af4b-c7ba34d04acc",{"content":"Without posting the website link anywhere but on Nostr, https://nostur.com/test1.mp4  it’s already received thousands of unique visits.","created_at":1682708743,"id":"5cae40612bdec6e77cf762dc817fe5535e4a3f7e1fc0597bddedc28bee0a7ffc","kind":1,"pubkey":"fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52","sig":"2a46c838114fb888a00c98649737b785f718206f55db0494564af51ab1b071c954dc4498fe59d04cc1024a2857610dc925615c3fe70bc685e3c8001696f48b7e","tags":[["p","c48e29f04b482cc01ca1f9ef8c86ef8318c059e0e9353235162f080f26e14c11"]]}]"###])
        }) {
            NavigationStack {
                if let p1 = PreviewFetcher.fetchNRPost("5cae40612bdec6e77cf762dc817fe5535e4a3f7e1fc0597bddedc28bee0a7ffc") {
                    let lvm = LVM(pubkeys: Set<String>(), listId: "Test")
                    let _ = lvm.nrPostLeafs = [p1]
                    SnapshotTest(lvm: lvm)
                }
            }
        }
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
