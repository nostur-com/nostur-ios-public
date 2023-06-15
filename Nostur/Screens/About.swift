//
//import SwiftUI
//
//struct About: View {
//    
//    let items = [
//        LicensedItem(title: "KeychainAccess", author: "kishikawa katsumi", url: "https://github.com/kishikawakatsumi/KeychainAccess"),
//        LicensedItem(title: "Nuke", author: "Alex Grebenyuk", url: "https://github.com/kean/Nuke"),
//        LicensedItem(title: "secp256k1", author: "GigaBitcoin LLC", url: "https://github.com/GigaBitcoin/secp256k1.swift")
//    ]
//    
//    var body: some View {
//        List {
//            ForEach(items) { item in
//                VStack(alignment: .leading) {
//                    Text("\(item.title) by **\(item.author)**")
//                        .lineLimit(1)
//                    Text(try! AttributedString(markdown: "[\(item.url)](\(item.url))")).lineLimit(1)
//                }
//            }
//        }
//    }
//}
//
//struct About_Previews: PreviewProvider {
//    static var previews: some View {
//        About()
//    }
//}
//
//struct LicensedItem: Identifiable {
//    var id:String { url }
//    let title:String
//    let author:String
//    let url:String
//}
