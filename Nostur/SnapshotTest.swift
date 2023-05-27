////
////  SnapshotTest.swift
////  Nostur
////
////  Created by Fabian Lachman on 27/05/2023.
////
//
//import SwiftUI
//import UIKit
//
//struct SnapshotTest: View {
//    var body: some View {
//        MyCollectionView()
//    }
//}
//
//struct SnapshotTest_Previews: PreviewProvider {
//    static var previews: some View {
//        SnapshotTest()
//            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
//    }
//}
//
//struct MyCollectionView: UIViewRepresentable {
//    
//    func makeUIView(context: Context) -> UICollectionView {
//        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
//            var config = UICollectionLayoutListConfiguration(appearance: .plain)
//            config.showsSeparators = false
//            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
//            section.contentInsets = .zero
//            return section
//        }
//        
//        layout.configuration.scrollDirection = .vertical
//        
//        let view  = UICollectionView(frame: .zero, collectionViewLayout: layout)
//        view.delegate = context.coordinator
//        
//        
//        return view
//    }
//    
//    func updateUIView(_ uiView: UICollectionView, context: Context) {
//        
//    }
//    
//    typealias UIViewType = UICollectionView
//    
//    func makeCoordinator() -> Coordinator {
//        return Coordinator(parent: self)
//    }
//    
//    class Coordinator: NSObject, UICollectionViewDelegate {
////        var collectionView:UICollectionView
//        var parent:MyCollectionView
//        
//        init(parent:MyCollectionView) {
//            self.parent = parent
//        }
//        
//        
//    }
//
//}
