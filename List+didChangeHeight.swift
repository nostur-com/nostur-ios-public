//
//  List+didScroll.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/02/2023.
//

import SwiftUI
import Introspect
import Combine

//struct ListDidScrollViewModifier: ViewModifier {
//
//    class ViewModel: ObservableObject {
//        @Published var contentOffset: CGPoint = .zero
//        var contentOffsetSubscription: AnyCancellable?
//
//        func subscribe(collectionView: UICollectionView) {
//              contentOffsetSubscription = collectionView.publisher(for: \.contentOffset)
//                .sink { [weak self] contentOffset in
//                self?.contentOffset = contentOffset
//              }
//        }
//    }
//
//    @StateObject var viewModel = ViewModel()
//    var didScroll: (CGPoint) -> Void
//
////    func body(content: Content) -> some View {
////        content
////            .introspect(selector: TargetViewSelector.ancestorOrSiblingContaining, customize: { (collectionView: UICollectionView) in
////                if viewModel.contentOffsetSubscription == nil {
////                    viewModel.contentOffsetSubscription = collectionView.publisher(for: \.contentOffset)
////                        .sink { contentOffset in
////                            didScroll(contentOffset)
////                        }
////                }
////            })
////    }
//
//    func body(content: Content) -> some View {
//        content
//            .introspect(selector: TargetViewSelector.ancestorOrSiblingContaining, customize: { (collectionView: UICollectionView) in
//            if viewModel.contentOffsetSubscription == nil {
//              viewModel.subscribe(collectionView: collectionView)
//            }
//          })
//          .onReceive(viewModel.$contentOffset) { contentOffset in
//            didScroll(contentOffset)
//          }
//      }
//}

struct ListDidChangeHeightViewModifier: ViewModifier {
    
    class ViewModel: ObservableObject {
        @Published var contentHeight:CGFloat = 0.0
        var contentHeightSubscription: AnyCancellable?
        
        func subscribe(collectionView: UICollectionView) {
            contentHeightSubscription = collectionView.publisher(for: \.contentSize)
                .debounce(for: .seconds(0.01), scheduler: RunLoop.main)
                .sink { [weak self] contentSize in
                    self?.contentHeight = contentSize.height
              }
        }
    }
    
    @StateObject var viewModel = ViewModel()
    var didChangeHeight: (CGFloat) -> Void
    
    func body(content: Content) -> some View {
        content
            .introspect(selector: TargetViewSelector.ancestorOrSiblingContaining, customize: { (collectionView: UICollectionView) in
                if viewModel.contentHeightSubscription == nil {
              viewModel.subscribe(collectionView: collectionView)
            }
          })
          .onReceive(viewModel.$contentHeight) { contentHeight in
            didChangeHeight(contentHeight)
          }
      }
    
//    func body(content: Content) -> some View {
//        content
//            .introspect(selector: TargetViewSelector.ancestorOrSiblingContaining, customize: { (collectionView: UICollectionView) in
//                if viewModel.contentHeightSubscription == nil {
//                    viewModel.contentHeightSubscription = collectionView.publisher(for: \.contentSize)
//                        .debounce(for: .seconds(0.01), scheduler: RunLoop.main)
//                        .sink { contentSize in
//                            didChangeHeight(contentSize.height)
//                        }
//                }
//            })
//    }
}

extension List {
//    func didScroll(_ didScroll: @escaping (CGPoint) -> Void) -> some View {
//        self.modifier(ListDidScrollViewModifier(didScroll: didScroll))
//    }
    func didChangeHeight(_ didChangeHeight: @escaping (CGFloat) -> Void) -> some View {
        self.modifier(ListDidChangeHeightViewModifier(didChangeHeight: didChangeHeight))
    }
}
