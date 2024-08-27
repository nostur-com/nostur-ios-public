//
//  AccountQR.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/08/2024.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct AccountQR: View {
    
    public let npub: String
    public var nip05: String?
    public var qrUrl: String {
        "nostr:\(npub)"
    }
    
    @State private var tapped1 = false
    @State private var tapped2 = false
    
    var body: some View {
        VStack {
            if let qrCodeImage = generateQRCode(from: qrUrl) {
                qrCodeImage
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .onTapGesture {
                        guard let url = URL(string: qrUrl) else { return }
                        UIApplication.shared.open(url)
                    }
            } else {
                Text("Failed to generate QR Code")
            }
            HStack {
                Text(npub)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: tapped1 ? "doc.on.doc.fill" : "doc.on.doc")
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .onTapGesture {
                UIPasteboard.general.string = npub
                tapped1 = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    tapped1 = false
                }
            }
            if let nip05 {
                HStack {
                    Text(nip05)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: tapped2 ? "doc.on.doc.fill" : "doc.on.doc")
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIPasteboard.general.string = nip05
                    tapped2 = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        tapped2 = false
                    }
                }
            }
        }
        .padding()
    }
}

#Preview {
    AccountQR(npub: "npub1n0sturny6w9zn2wwexju3m6asu7zh7jnv2jt2kx6tlmfhs7thq0qnflahe", nip05: "fabian@nostur.com")
}


func generateQRCode(from string: String) -> Image? {
    let data = Data(string.utf8)
    
    let filter = CIFilter.qrCodeGenerator()
    filter.setValue(data, forKey: "inputMessage")
    
    // Get the output CIImage
    if let outputImage = filter.outputImage {
        let context = CIContext()
        if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            // Convert the CIImage to a SwiftUI Image
            return Image(uiImage: UIImage(cgImage: cgImage))
        }
    }
    
    return nil
}
