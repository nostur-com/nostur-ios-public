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
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    public var token:String
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
                .buttonStyle(NRButtonStyle(style: .borderedProminent))
                .cornerRadius(20)

                Group {
//                    if let memo = token.memo {
//                        Text(memo)
//                    }
                    
                    if let mint = token.primaryMintHost {
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
            do {
                let cashuToken = try decodeCashuToken(from: token)
                
                Task { @MainActor in
                    self.cashuToken = cashuToken
                    
                    let sats = Double(cashuToken.totalAmount)
                    let btcPrice = ExchangeRateModel.shared.bitcoinPrice
                    self.fiatPrice = String(format: "($%.02f)", sats / 100_000_000 * btcPrice)
                }
            } catch {
                print("Invalid Cashu token: \(error)")
                // Show user-friendly message
            }
        }
        
    }
}


#Preview {
    CashuTokenView(token: "cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vbGVnZW5kLmxuYml0cy5jb20vY2FzaHUvYXBpL3YxL0FwdEROQUJOQlh2OGdwdXl3aHg2TlYiLCJwcm9vZnMiOlt7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJMd3BZWjdNaTBRd1dXNXZPT2p2ZmhXVnYrU3pjenlaTnR1YzN5NXBwQlRZPSIsIkMiOiIwMzkyYjdmOTcwMTc2NzA3Y2U2ZmJmZjE0Y2U2ZTZhNzdjNmRjY2JkMjQ0NTMzNzNhNTU4YmQ5MmMyYWIyMzk2OTYifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo0LCJzZWNyZXQiOiJRNktTZjR2YXVnWjl3V0o1dWFRODFBY1pDSTVFTWRpcWhIcjhyQy84VklnPSIsIkMiOiIwMmQzMDExNzY0NmM4NDhlZmYwNDBjNWI0ZDcwNmZiMjZmYWZiNmYwNjQwZjA1MTZlMjQ5NmI2MDNiOTkzOTY5MmUifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxNiwic2VjcmV0IjoiMUdsUlEwdWR0WXIraUlRdFV0Y25XdDZ4UUUvS3J0NHFDditYWWxoSXlJND0iLCJDIjoiMDM4MDIyYTc5NDhiZjY0NzNhNGQ3ZjMyOTAwM2Q0ODQ3ZjE1MTYyMWQ0YzA5N2IxZjVjNDJhY2Q5MTc4MjkzMDk3In1dfV0sIm1lbW8iOiJTZW50IHZpYSBlTnV0cy4ifQ")
}


#Preview("Cashu token in post") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.parseMessages([
            ###"["EVENT", "NEW", {"tags":[["client","Damus Notedeck"]],"pubkey":"2d9873b25bf2dda6141684d44d5eb76af59f167788a58e363ab1671fefee87f2","created_at":1766547122,"kind":1,"id":"b650330f3ed4789399723d3569ef45dabc9f0626be9bb1173a78e9a97aba6113","content":"cashuBo2FteBxodHRwczovL21pbnQubW91bnRhaW5sYWtlLmlvYXVjc2F0YXSBomFpSACKqMPqfkIgYXCFpGFhCGFzeEA2Mzk1MjUwNzk2MzNmNjcyYTEwMTY5OTM0NDMwYTg0NTQxMzI0NTkwYjAwNjRjYjZlNTE1MjQ5YWFiZjAxNjM5YWNYIQNmVKUZCe54m8CoRPt3_LpIL-Y-b9ckTgsSMXWaYY2M3WFko2FlWCAIkHouDkmd9kJG67W_UTUMdazaUkK2dvlApOczWki-hWFzWCCqZw0mZQr11eRPvLoP5134h5jJ0al0hG1UcmfECRuc-2FyWCAFu0bX2_wiM0_mfHiEtnQbKUQDOYrHc8cgiPPPheYGSKRhYQhhc3hAYjRmZDMxZjNlNDdiYjllYmY1N2MyMjgwZTMyOWVhNjcyMjM4MzlkOTgxYjFkMDY4YjBmZTQ4YjE0YzQ0YzBmOWFjWCED3QzJOjoMCInQCR7qOG6Rg8Lx6reHO2p-qwoZZEHgjR5hZKNhZVggXVCQWlks2eoZ2cfXk2CNUKYOpmNE62n7iBZ275aHj2Fhc1gg6ktRxxRVu-Uzemgp9jDBfj5UzVjDWGPjMg2_mL4UGhxhclggRGlWkfpw5NegFRk-pIXyijELMM-EyJknHTsl2aMlcO6kYWECYXN4QDc3ZWZiNDdlNjA3NzQyZDhjNGQ0MTM2MjEwNDM3ZjUxZTMwZmMzZDQ1ZTVkM2E5NzM0MTQxZGMxZDI5MTkyYTVhY1ghAjlKQN_V9fAyUS3mIE4IGMNPJuWg7VHsUp8l7ccFcTLGYWSjYWVYIOyrs5CN-R-M1KuO5bWHezB9lus1nXMgF8vfuTd-Pn2RYXNYILdKFrBaXUEoiihOP5AkmndGd6TC2BEKDy6q7lXn2z7rYXJYILK6R1tvmKi8-l72xDTKmUlDAldp51JFrLIq3BQqIIQepGFhAmFzeEA0NTQ2MWYxMzE4OTc5Njc0MDllZjkzMjdiNThkYzQ2ZThmMDQ0ZmUwZmFmNjdhYTFiMDcxNmMzMmY3MDM2NDYyYWNYIQKOd178WzIHSYMpq53ou9kdHhK_ocIvoHZfW8FWyVLb9WFko2FlWCDKsBNhhQImXkC9FjCdrrnHvGdHh0e2Xbwi9WiodcsIpmFzWCAmVB6v5hSBuZLmd8JgW8fdJ8rnNaKOjEhOJ6g7QVBcvGFyWCCSkcgrjWaPdKk5JTPM98ewg9WvHUqWERiximlUxKSsYKRhYQJhc3hAZDIwMTQ0ZTlkNjA2NWM1N2NjNTVlYTA2OGU2ZWI4ZDE0Y2U5ZGZkYzNlOGU0N2FmNTQ0Y2Y3ODVjNzVkMzUwOGFjWCEDgT2SqBEfYu2BvCdRmusYYOJygjA51aaUOTTorAVwxSRhZKNhZVggoIPNGWvpHx9An3R-ddNeXdi-Uyomge_7cdK1HuvCCuNhc1gg0jrtrhEvLAgLgGEvgX0-JI-Cyymsbx6NGfJ6edXqLkthclggDmfpd2dxfuRv_80Tq2YeTgzgCtBtqoUQZYqdN9kfIZg","sig":"b20cc6809b08fd602f20cd4096623a207c16c6b84c50e75e744caee945fca5db13a821b9d33c5b3c09ec72bcf018934460385749749030f26f6f99173b0d114a"}]"###,
            ###"["EVENT", "CASHU-EXAMPLE", {"pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","content":"Testing\n\ncashuAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbeyJpZCI6IkkyeU4raVJZZmt6VCIsImFtb3VudCI6NjQsIkMiOiIwMjE5YWFkZWY3YmNmODQzM2E1ZmM4MjQwZTIwNTViZGFmN2RjOTA0ZDVjNzcwZTk2N2M0ODlmZDdjOGVjM2FiY2YiLCJzZWNyZXQiOiJRS3czMWRxdmhVeEZDWEEwYUlQcHowUVBsWjRwSVFraXJRaVdOa1FCU0tzPSJ9LHsiaWQiOiJJMnlOK2lSWWZrelQiLCJhbW91bnQiOjI1NiwiQyI6IjAzZjY1MzA5MDRlZWE2MzQyNDMyOTc5MmQwNDIzNzg3MzhjMmRjNjBmZDEyOWU3YzQ1N2M0OTM2NDM3MTlkNzAyNyIsInNlY3JldCI6InljM05KTnkzcVRVcWV6WXo4cHFrbFE2TDQ3MFNlbi9TbTVxbEVqQm1aNU09In1dLCJtaW50IjoiaHR0cHM6Ly84MzMzLnNwYWNlOjMzMzgifV19","id":"815bc97d86bbaa5a5a152b6298dff1ec5c068d1235bfd5744dc51bc4927fe569","created_at":1700953900,"sig":"06104e9b09c861e1c998780fd0a24f933f295a07dc186183aa3be68f7589376d64d859a06929e41bf0643416ab968e871ff902af361d06bd00d16f7a192223e8 and cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vbGVnZW5kLmxuYml0cy5jb20vY2FzaHUvYXBpL3YxL0FwdEROQUJOQlh2OGdwdXl3aHg2TlYiLCJwcm9vZnMiOlt7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJMd3BZWjdNaTBRd1dXNXZPT2p2ZmhXVnYrU3pjenlaTnR1YzN5NXBwQlRZPSIsIkMiOiIwMzkyYjdmOTcwMTc2NzA3Y2U2ZmJmZjE0Y2U2ZTZhNzdjNmRjY2JkMjQ0NTMzNzNhNTU4YmQ5MmMyYWIyMzk2OTYifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo0LCJzZWNyZXQiOiJRNktTZjR2YXVnWjl3V0o1dWFRODFBY1pDSTVFTWRpcWhIcjhyQy84VklnPSIsIkMiOiIwMmQzMDExNzY0NmM4NDhlZmYwNDBjNWI0ZDcwNmZiMjZmYWZiNmYwNjQwZjA1MTZlMjQ5NmI2MDNiOTkzOTY5MmUifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxNiwic2VjcmV0IjoiMUdsUlEwdWR0WXIraUlRdFV0Y25XdDZ4UUUvS3J0NHFDditYWWxoSXlJND0iLCJDIjoiMDM4MDIyYTc5NDhiZjY0NzNhNGQ3ZjMyOTAwM2Q0ODQ3ZjE1MTYyMWQ0YzA5N2IxZjVjNDJhY2Q5MTc4MjkzMDk3In1dfV0sIm1lbW8iOiJTZW50IHZpYSBlTnV0cy4ifQ","kind":1,"tags":[["client","Nostur"]]}]"###,
            ###"["EVENT", "CASHU-EXAMPLE2", {"pubkey":"0d2a0f56c89fd364b89723ffe76102394010ca3fe48b804f0df86e2cef40df51","tags":[["r","https://video.nostr.build/4e1f01dc116afeef3a7e02cb19467121072c645d6205f5729effaf23117a0c4b.mp4"],["imeta","url https://video.nostr.build/4e1f01dc116afeef3a7e02cb19467121072c645d6205f5729effaf23117a0c4b.mp4","m video/mp4","alt Verifiable file url","x 012ebd7b82263481be485c63b906913b4724df6bb3a712d6a7bd2bc91869d6c6","size 14651074","dim 720x1280","blurhash ]6H2AvQ=8_4=%50J-A-.}=Ne00IT_M4nRikYGIRQ.7IVx_tm9uk@NI^jpH9FI:RP$gITD%%g?aELRP-;iwM{t2XT%NIUR.","ox 4e1f01dc116afeef3a7e02cb19467121072c645d6205f5729effaf23117a0c4b"]],"sig":"b9babfbc0cc1331d3d0b5e3642e51f8411b69a50a8100a79ce5906c2fd936308458aa50cc5dc1647b18fa9ca6904efb9cc1fddbed9a2150f1fda7f156a837e5b","id":"23cfeb2e3b4df14d0af1f71311cbb750a2bc6febbc8b42e2fad3892344eef504","content":"cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vbWludC5taW5pYml0cy5jYXNoL0JpdGNvaW4iLCJwcm9vZnMiOlt7ImlkIjoiMDA1MDA1NTBmMDQ5NDE0NiIsImFtb3VudCI6MSwic2VjcmV0IjoiTWYvYnFEMjgvYTgrKzZyR3M1TGx1K2FMZE9uZGZtT0VtOWh2ZUtIRWEyND0iLCJDIjoiMDNhOWVmMmEzNThiMDU2MmY5Y2MxYmU0MWU5MGFkYjIxOTlmNGVkMTc0YmQzZmZmNjczZmU5YzNkMjVjZmNiN2IxIn0seyJpZCI6IjAwNTAwNTUwZjA0OTQxNDYiLCJhbW91bnQiOjQsInNlY3JldCI6IjBtZXp6bjl0c1dpa0orTnlLL2IzUDFrSTRkMGh5dGtJQ0VRTktXNXlubDA9IiwiQyI6IjAzYTFiZDQ4MDYwZjhmZmIyOTc3NDFiOTQxYmUyYWIxZGI1MjdlYTA2ZWUwOWFhOGE5N2I5MDVlYjMyY2U4MTY4YiJ9LHsiaWQiOiIwMDUwMDU1MGYwNDk0MTQ2IiwiYW1vdW50IjoxNiwic2VjcmV0IjoidzZHb0NZTUhJWTdPc2xYVDc4K08vQVJEQWFMQk45UkFmMmozalJ5S2ZWRT0iLCJDIjoiMDMwNGIyMTMzYmUwYzZmMmYzM2IwZTYxNzk3ZGVjOGE2YmUxOTk5ODQ5ODRjMTcyMDJjNzBkMjc4NjNiYTNiOTRiIn1dfV0sIm1lbW8iOiLwn6Wc8J-lnPCfpZzwn6Wc8J-lnPCfpZzwn6Wc8J-lnPCfpZzwn6WcIn0 https://video.nostr.build/4e1f01dc116afeef3a7e02cb19467121072c645d6205f5729effaf23117a0c4b.mp4","kind":1,"created_at":1727637728}]"###])
    }) {
        ScrollView {
            VStack {
                if let post = PreviewFetcher.fetchNRPost("b650330f3ed4789399723d3569ef45dabc9f0626be9bb1173a78e9a97aba6113") {
                    PostRowDeletable(nrPost: post, theme: Themes.default.theme)
                }
                if let post = PreviewFetcher.fetchNRPost("23cfeb2e3b4df14d0af1f71311cbb750a2bc6febbc8b42e2fad3892344eef504") {
                    PostRowDeletable(nrPost: post, theme: Themes.default.theme)
                }
                if let post = PreviewFetcher.fetchNRPost("815bc97d86bbaa5a5a152b6298dff1ec5c068d1235bfd5744dc51bc4927fe569") {
                    PostRowDeletable(nrPost: post, theme: Themes.default.theme)
                }
            }
        }
        .padding(10)
    }
}
