////
////  ZapButton.swift
////  Nostur
////
////  Created by Fabian Lachman on 14/02/2023.
////
//
//import SwiftUI
//
//struct ZapButton: View {
//    
//    @Environment(\.openURL) var openURL
//    var event:Event
//    @State var isLoading = false
//    
//    @State var payAmountSelectorShown = false
//    @State var min:UInt64 = 0
//    @State var max:UInt64 = 5000000
//    @State var callback = ""
//    
//    var body: some View {
//        if (event.contact?.lud16 != nil && event.contact!.lud16 != "") {
//            Button {
//                isLoading = true
//                let lud16 = event.contact!.lud16!
//                Task.detached(priority: .background) {
//                    do {
//                        let response = try await LUD16.getCallbackUrl(lud16: lud16)
//                        await MainActor.run {
//                            // Make sure at least 1 sat, and not more than 2000000 sat (around $210)
//                            min = ((response.minSendable ?? 1000) < 1000 ? 1000 : (response.minSendable ?? 1000)) / 1000
//                            max = ((response.maxSendable ?? 1000000000) > 1000000000 ? 1000000000 : (response.maxSendable ?? 1000000000)) / 1000
//                            if response.callback != nil {
//                                callback = response.callback!
//                                payAmountSelectorShown = true
//                                isLoading = false
//                            }
//                        }
//                    }
//                    catch {
//                        print("problem in lnurlp")
//                        print(error)
//                    }
//                }
//            } label: {
//                if isLoading {
//                    ProgressView()
//                        .colorInvert()
//                }
//                else {
//                    Text("⚡️")
//                }
//            }
//            .frame(width: 40, height: 30)
//            .font(.caption.weight(.heavy))
////            .foregroundColor(Color("BackgroundColor"))
//            .background(Color("BackgroundColor"))
//            .cornerRadius(20)
//            .overlay {
//                RoundedRectangle(cornerRadius: 20)
//                    .stroke(.gray, lineWidth: 1)
//            }
//            .sheet(isPresented: $payAmountSelectorShown) {
//                PaymentAmountSelector(min:min, max:max) { amount in
//                    Task.detached(priority: .background) {
//                        do {
//                            let response = try await LUD16.getInvoice(url:callback, amount:UInt64(amount * 1000))
//                            
//                            if response.pr != nil {
//                                await MainActor.run {
//                                    openURL(URL(string: "lightning:\(response.pr!)")!)
//                                }
//                            }
//                        }
//                        catch {
//                            print("problem fetching ln invoice")
//                            print(error)
//                        }
//                    }
//                }
//            }
//        }
//        else {
//            EmptyView()
//        }
//    }
//}
//
//struct ZapButton_Previews: PreviewProvider {
//    static var previews: some View {
//        let event = PreviewFetcher.fetchEvent()!
//        
//        ZapButton(event: event)
//            .withPreviewEnvironment()
//    }
//}
