//
//  ImposterChecker.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/07/2023.
//

import SwiftUI

func compareImages(image1: UIImage, image2: UIImage) -> CGFloat {
    guard let cgImage1 = image1.cgImage, let cgImage2 = image2.cgImage,
          let data1 = cgImage1.dataProvider?.data as Data?,
          let data2 = cgImage2.dataProvider?.data as Data? else {
        return 1.0
    }
    
    let pixelCount = Int(image1.size.width * image1.size.height)
    let pixelData1 = [UInt8](data1)
    let pixelData2 = [UInt8](data2)

    var mae: CGFloat = 0.0
    
    for i in stride(from: 0, to: pixelCount * 4, by: 4) {
        let r1 = CGFloat(pixelData1[i])
        let g1 = CGFloat(pixelData1[i + 1])
        let b1 = CGFloat(pixelData1[i + 2])
        
        if i < pixelData2.count {
            let r2 = CGFloat(pixelData2[i])
            let g2 = CGFloat(pixelData2[i + 1])
            let b2 = CGFloat(pixelData2[i + 2])
            
            let diffR = abs(r1 - r2)
            let diffG = abs(g1 - g2)
            let diffB = abs(b1 - b2)
            
            let diff = (diffR + diffG + diffB) / (3 * 255)
            mae += diff
        }
    }
    
    mae /= CGFloat(pixelCount)
    
    return mae
}

func pfpsAreSimilar(imposter:String, real:String, threshold:Double = 0.1) async -> Bool {
    var impostorImage:UIImage?
    var realImage:UIImage?
    
    let impostorReq = pfpImageRequestFor(imposter)
    let realReq = pfpImageRequestFor(real)
    
    let task1 = ImageProcessing.shared.pfp.imageTask(with: impostorReq)
    if let response = try? await task1.response {
        impostorImage = response.container.image //.preparingForDisplay()
    }
    
    let task2 = ImageProcessing.shared.pfp.imageTask(with: realReq)
    if let response = try? await task2.response {
        realImage = response.container.image //.preparingForDisplay()
    }
    
    guard let impostorImage = impostorImage, let realImage = realImage else { return false }
    
    let mae = compareImages(image1: impostorImage, image2: realImage)

    L.og.debug("😎 ImposterChecker - imagesAreSimilar: \(mae)")
    print("😎 ImposterChecker - imagesAreSimilar: \(mae)")
    if (mae == 0.0) { return false }
    if mae <= threshold {
        return true
    } else {
        return false
    }
}

struct ImposterTesterView: View {
    var body: some View {
        Text("test1")
            .task {
                let imposter = "https://cdn.nostr.build/i/eb8d33b383e103c1143a040dda69729d19e8e3115735c3ef3a283b08723b0a6c.jpg"
                let real = "https://nostr.build/i/p/nostr.build_6b9909bccf0f4fdaf7aacd9bc01e4ce70dab86f7d90395f2ce925e6ea06ed7cd.jpeg"
                
                let similar = await pfpsAreSimilar(imposter: imposter, real: real)
                print("are they similar: \(similar)")
            }
    }
}

struct Previews_ImpostorChecker_Previews: PreviewProvider {
    static var previews: some View {
        ImposterTesterView()
    }
}


func isSimilar(string1: String, string2: String, percent:Double = 0.95) -> Bool {
    return string1.distance(between: string2) >= percent
}
