//
//  CashuTokenView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/11/2023.
//

import SwiftUI

// Copy pasta from LightningInvoice

let CASHU_REDEEM_URL = "https://redeem.cashu.me/?token={TOKEN}&lightning={LUD16}" // &autopay=yes? TODO: Make not hardcoded

struct CashuTokenView: View {
    @Environment(\.openURL) private var openURL
    public var token:String
    public var theme:Theme
    @State private var divider: Double = 1 // 1 = SATS, 100000000 = BTC
    @State private var fiatPrice = ""
    @State private var cashuToken: CashuToken?
    
    var body: some View {
        VStack {
            if let token = cashuToken, token.totalAmount > 0 {
                Text("Cashu (Bitcoin) 🥜", comment:"Title of cashu redeem card").font(.caption)
                Divider()
                Text("\((Double(token.totalAmount)/divider).clean.description) \(divider == 1 ? "sats" : "BTC") \(fiatPrice)")
                    .font(.title3).padding(.bottom, 10)
                    .onTapGesture {
                        divider = divider == 1 ? 100000000 : 1
                    }
                
                Button {
                    let lud16 = account()?.lud16 ?? ""
                    let redeemUrl = CASHU_REDEEM_URL.replacingOccurrences(of: "{TOKEN}", with: self.token)
                                                    .replacingOccurrences(of: "{LUD16}", with: lud16)
                    guard let url = URL(string: redeemUrl) else { return }
                    openURL(url)
                } label: {
                    Text("Redeem", comment:"Button to redeem a Cashu token").frame(minWidth: 150)
                }
                .buttonStyle(NRButtonStyle(theme: theme, style: .borderedProminent))
                .cornerRadius(20)

                Group {
//                    if let memo = token.memo {
//                        Text(memo)
//                    }
                    
                    if let mint = token.mint {
                        Text(mint)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            else {
                Text("Unable to decode Cashu token", comment:"Error message")
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [.orange, .red],
                                   startPoint: .top,
                                   endPoint: .center).opacity(0.3))
        .cornerRadius(20)
        .task {
            Task {
                let a = Data(base64Encoded: String(token.dropFirst(6)))
                let b = Data(base64Encoded: String(token.dropFirst(6) + "="))
                let c = Data(base64Encoded: String(token.dropFirst(6) + "=="))
                
                guard let data = ((a ?? b) ?? c) else { return }
                 
                let decoder = JSONDecoder()
                guard let cashuToken = try? decoder.decode(CashuToken.self, from: data) else { return }
                Task { @MainActor in
                    self.cashuToken = cashuToken
                    self.fiatPrice = String(format: "($%.02f)",(Double(cashuToken.totalAmount) / 100000000 * ExchangeRateModel.shared.bitcoinPrice))
                }
            }
        }
        
    }
}


#Preview {
    CashuTokenView(token: "cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vbGVnZW5kLmxuYml0cy5jb20vY2FzaHUvYXBpL3YxL0FwdEROQUJOQlh2OGdwdXl3aHg2TlYiLCJwcm9vZnMiOlt7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJMd3BZWjdNaTBRd1dXNXZPT2p2ZmhXVnYrU3pjenlaTnR1YzN5NXBwQlRZPSIsIkMiOiIwMzkyYjdmOTcwMTc2NzA3Y2U2ZmJmZjE0Y2U2ZTZhNzdjNmRjY2JkMjQ0NTMzNzNhNTU4YmQ5MmMyYWIyMzk2OTYifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo0LCJzZWNyZXQiOiJRNktTZjR2YXVnWjl3V0o1dWFRODFBY1pDSTVFTWRpcWhIcjhyQy84VklnPSIsIkMiOiIwMmQzMDExNzY0NmM4NDhlZmYwNDBjNWI0ZDcwNmZiMjZmYWZiNmYwNjQwZjA1MTZlMjQ5NmI2MDNiOTkzOTY5MmUifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxNiwic2VjcmV0IjoiMUdsUlEwdWR0WXIraUlRdFV0Y25XdDZ4UUUvS3J0NHFDditYWWxoSXlJND0iLCJDIjoiMDM4MDIyYTc5NDhiZjY0NzNhNGQ3ZjMyOTAwM2Q0ODQ3ZjE1MTYyMWQ0YzA5N2IxZjVjNDJhY2Q5MTc4MjkzMDk3In1dfV0sIm1lbW8iOiJTZW50IHZpYSBlTnV0cy4ifQ", theme: Themes.default.theme)
}


#Preview("Cashu token in post") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.parseMessages([
            ###"["EVENT", "CASHU-EXAMPLE", {"pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","content":"Testing\n\ncashuAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbeyJpZCI6IkkyeU4raVJZZmt6VCIsImFtb3VudCI6NjQsIkMiOiIwMjE5YWFkZWY3YmNmODQzM2E1ZmM4MjQwZTIwNTViZGFmN2RjOTA0ZDVjNzcwZTk2N2M0ODlmZDdjOGVjM2FiY2YiLCJzZWNyZXQiOiJRS3czMWRxdmhVeEZDWEEwYUlQcHowUVBsWjRwSVFraXJRaVdOa1FCU0tzPSJ9LHsiaWQiOiJJMnlOK2lSWWZrelQiLCJhbW91bnQiOjI1NiwiQyI6IjAzZjY1MzA5MDRlZWE2MzQyNDMyOTc5MmQwNDIzNzg3MzhjMmRjNjBmZDEyOWU3YzQ1N2M0OTM2NDM3MTlkNzAyNyIsInNlY3JldCI6InljM05KTnkzcVRVcWV6WXo4cHFrbFE2TDQ3MFNlbi9TbTVxbEVqQm1aNU09In1dLCJtaW50IjoiaHR0cHM6Ly84MzMzLnNwYWNlOjMzMzgifV19","id":"815bc97d86bbaa5a5a152b6298dff1ec5c068d1235bfd5744dc51bc4927fe569","created_at":1700953900,"sig":"06104e9b09c861e1c998780fd0a24f933f295a07dc186183aa3be68f7589376d64d859a06929e41bf0643416ab968e871ff902af361d06bd00d16f7a192223e8 and cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vbGVnZW5kLmxuYml0cy5jb20vY2FzaHUvYXBpL3YxL0FwdEROQUJOQlh2OGdwdXl3aHg2TlYiLCJwcm9vZnMiOlt7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJMd3BZWjdNaTBRd1dXNXZPT2p2ZmhXVnYrU3pjenlaTnR1YzN5NXBwQlRZPSIsIkMiOiIwMzkyYjdmOTcwMTc2NzA3Y2U2ZmJmZjE0Y2U2ZTZhNzdjNmRjY2JkMjQ0NTMzNzNhNTU4YmQ5MmMyYWIyMzk2OTYifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo0LCJzZWNyZXQiOiJRNktTZjR2YXVnWjl3V0o1dWFRODFBY1pDSTVFTWRpcWhIcjhyQy84VklnPSIsIkMiOiIwMmQzMDExNzY0NmM4NDhlZmYwNDBjNWI0ZDcwNmZiMjZmYWZiNmYwNjQwZjA1MTZlMjQ5NmI2MDNiOTkzOTY5MmUifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxNiwic2VjcmV0IjoiMUdsUlEwdWR0WXIraUlRdFV0Y25XdDZ4UUUvS3J0NHFDditYWWxoSXlJND0iLCJDIjoiMDM4MDIyYTc5NDhiZjY0NzNhNGQ3ZjMyOTAwM2Q0ODQ3ZjE1MTYyMWQ0YzA5N2IxZjVjNDJhY2Q5MTc4MjkzMDk3In1dfV0sIm1lbW8iOiJTZW50IHZpYSBlTnV0cy4ifQ","kind":1,"tags":[["client","Nostur"]]}]"###])
    }) {
        VStack {
            if let post = PreviewFetcher.fetchNRPost("815bc97d86bbaa5a5a152b6298dff1ec5c068d1235bfd5744dc51bc4927fe569") {
                PostRowDeletable(nrPost: post)
            }
        }
        .padding(10)
    }
}
