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
    
    @State var vm = ViewModel()
    
    var body: some View {
        VStack {
            Button("Add to top") {
                vm.data.insert(UUID().uuidString, at: 0)
            }
            Button("Add to bottom") {
                vm.data.append(UUID().uuidString)
            }
            MyCollectionView(vm: vm)
//                .frame(width: 300, height: 500)
//                .fixedSize()
        }
    }
}

class ViewModel: ObservableObject {
    @Published var data = ["1","2","3"]
}

struct SnapshotTest_Previews: PreviewProvider {
    static var previews: some View {
        SnapshotTest()
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}

enum SingleSectionT: CaseIterable {
    case main
}

public typealias NRID = String

struct MyCollectionView: UIViewControllerRepresentable {
    
    private var vm:ViewModel
    
    init(vm: ViewModel) {
        self.vm = vm
    }
    
    func makeUIViewController(context: Context) -> UICollectionViewController {
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.showsSeparators = false
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
            section.contentInsets = .zero
            return section
        }
        layout.configuration.scrollDirection = .vertical
                
        let controller = UICollectionViewController(collectionViewLayout: layout)
        controller.collectionView.delegate = context.coordinator
        context.coordinator.collectionView = controller.collectionView
        
        let dataSource = UICollectionViewDiffableDataSource<SingleSectionT, NRID>(collectionView: controller.collectionView) { collectionView, indexPath, itemIdentifier in
            print(indexPath.row)
            print(itemIdentifier)
            print(context.coordinator.data.count)
            return collectionView.dequeueConfiguredReusableCell(using: CellRegistration, for: indexPath, item: context.coordinator.data[indexPath.row])
        }
        
        context.coordinator.dataSource = dataSource
        
        
        var snapshot = NSDiffableDataSourceSnapshot<SingleSectionT, NRID>()
        snapshot.appendSections([SingleSectionT.main])
        snapshot.appendItems(context.coordinator.data, toSection: .main)
        dataSource.apply(snapshot)
        print("ddede")
        
        context.coordinator.dataSource = dataSource
        context.coordinator.listen()
        
        return controller
    }
    
    private var CellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, String> = {
        .init { cell, indexPath, item in
            cell.contentConfiguration = UIHostingConfiguration {
                Text(item)
                    .hCentered()
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
    
    class Coordinator: NSObject, UICollectionViewDelegate {

        var dataSource:UICollectionViewDiffableDataSource<SingleSectionT, NRID>?
        var collectionView:UICollectionView?
        var vm:ViewModel
        var data:[NRID] = []
        var subscriptions = Set<AnyCancellable>()
        
        init(parent: MyCollectionView) {
            self.vm = parent.vm
        }
        
        func listen() {
            // create data source
            vm.$data
                .sink { [weak self] data in
                    guard let self = self else { return }
                    self.data = data
                    var snapshot = NSDiffableDataSourceSnapshot<SingleSectionT, NRID>()
                    snapshot.appendSections([SingleSectionT.main])
                    snapshot.appendItems(data, toSection: .main)
                    print(data)
                    self.dataSource?.apply(snapshot)
                }
                .store(in: &subscriptions)
        }
        
        
    }

}



final class SnapshotSource<SectionType: Hashable,ItemType: Hashable>: UICollectionViewDiffableDataSource<SectionType, ItemType> { }
