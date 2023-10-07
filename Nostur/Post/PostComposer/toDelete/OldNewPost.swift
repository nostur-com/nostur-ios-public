////
////  NewPost.swift
////  Nostur
////
////  Created by Fabian Lachman on 11/02/2023.
////
//
//// TODO: Should add drafts and auto-save
//// TODO: Need to create better solution for typing @mentions
//
//import SwiftUI
//import Combine
//import PhotosUI
//
//struct NewPost: View {
//    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
//    @EnvironmentObject private var theme:Theme
//    let PLACEHOLDER = String(localized:"What's happening?", comment: "Placeholder text for typing a new post")
//    @Environment(\.dismiss) private var dismiss
//    
//    @StateObject private var vm = NewPostModel()
//    @StateObject private var ipm = ImagePickerModel()
//    
//    var body: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
//        VStack(spacing:0) {
//            if let account = vm.activeAccount {
//                VStack {
//                    HStack(alignment: .top) {
//                        
//                        
//                    }
//                    
//                }
//                
//
//                
//                
//                
//            }
////            else {
////                ProgressView()
////            }
//        }
////        .onAppear {
////            vm.activeAccount = account()
////        }
//    }
//}
//
//struct NewNote_Previews: PreviewProvider {
//    static var previews: some View {
//        PreviewContainer({ pe in
//            pe.loadAccounts()
//            pe.loadPosts()
//            pe.loadContacts()
//        }) {
//            VStack {
//                Button("New Post") { }
//                    .sheet(isPresented: .constant(true)) {
//                        NavigationStack {
////                            NewPost()
//                        }
//                    }
//            }
//        }
//    }
//}
//
//
//
