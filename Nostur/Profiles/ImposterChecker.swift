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
        guard i+2 < pixelData1.count, i+2 < pixelData2.count else { continue }
        
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

func pfpsAreSimilar(imposter:URL, real:URL, threshold:Double = 0.1) async -> Bool {
    guard imposter != real else { return true } // if urls are the same we don't need to check the actual images
    
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
//    print("😎 ImposterChecker - imagesAreSimilar: \(mae)")
    if (mae == 0.0) { return false }
    if mae <= threshold {
        return true
    } else {
        return false
    }
}

struct ImposterTesterView: View {
    var body: some View {
        Text(verbatim: "test1")
            .task {
                let imposter = "https://cdn.nostr.build/i/eb8d33b383e103c1143a040dda69729d19e8e3115735c3ef3a283b08723b0a6c.jpg"
                let real = "https://nostr.build/i/p/nostr.build_6b9909bccf0f4fdaf7aacd9bc01e4ce70dab86f7d90395f2ce925e6ea06ed7cd.jpeg"
                
                let similar = await pfpsAreSimilar(imposter: URL(string: imposter)!, real: URL(string: real)!)
                print("are they similar: \(similar)")
            }
    }
}

struct Previews_ImpostorChecker_Previews: PreviewProvider {
    static var previews: some View {
        ImposterTesterView()
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}


func isSimilar(string1: String, string2: String, percent:Double = 0.95) -> Bool {
    return string1.distance(between: string2) >= percent
}

class ImposterChecker {
    
    static let shared = ImposterChecker()
    
    public func runImposterCheck(contact: Contact, completion: @escaping (CouldBeImposterYes) -> Void) {
        guard shouldRunCheck(contact: contact) else { return }
        
        guard contact.picture != nil, let cPic = contact.pictureUrl else { return }
        guard let followingCache = NRState.shared.loggedInAccount?.followingCache else { return }
        
        let contactAnyName = contact.anyName.lowercased()
        let cPubkey = contact.pubkey
        let currentAccountPubkey = NRState.shared.activeAccountPublicKey
        
        bg().perform {
            guard let account = account() else { return }
            guard account.publicKey == currentAccountPubkey else { return }
            guard let (followingPubkey, similarFollow) = followingCache.first(where: { (pubkey: String, follow: FollowCache) in
                pubkey != cPubkey && isSimilar(string1: follow.anyName.lowercased(), string2: contactAnyName)
            }) else { return }
            
            guard similarFollow.pfpURL != nil, let wotPic = similarFollow.pfpURL else { return }
            
            L.og.debug("😎 ImposterChecker similar name: \(contactAnyName) - \(similarFollow.anyName)")
            
            Task.detached(priority: .background) {
                let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                guard similarPFP else { return }
                L.og.debug("😎 ImposterChecker similar PFP: \(cPic) - \(wotPic) - \(cPubkey)")
       
                DispatchQueue.main.async {
                    guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                    
                    contact.couldBeImposter  = similarPFP ? 1 : 0
                    
                    let similarToPubkey = similarPFP ? followingPubkey : nil
                    contact.similarToPubkey = similarToPubkey
                    
                    completion(CouldBeImposterYes(similarToPubkey: followingPubkey))
                }
            }
        }
    }
 
    public func runImposterCheck(nrContact: NRContact, completion: @escaping (CouldBeImposterYes) -> Void) {
        guard shouldRunCheck(nrContact: nrContact) else { return }
        
        guard let cPic = nrContact.pictureUrl else { return }
        guard let followingCache = NRState.shared.loggedInAccount?.followingCache else { return }
        
        let contactAnyName = nrContact.anyName.lowercased()
        let cPubkey = nrContact.pubkey
        let currentAccountPubkey = NRState.shared.activeAccountPublicKey
        
        bg().perform {
            guard let account = account() else { return }
            guard account.publicKey == currentAccountPubkey else { return }
            guard let (followingPubkey, similarFollow) = followingCache.first(where: { (pubkey: String, follow: FollowCache) in
                pubkey != cPubkey && isSimilar(string1: follow.anyName.lowercased(), string2: contactAnyName)
            }) else { return }
            
            guard similarFollow.pfpURL != nil, let wotPic = similarFollow.pfpURL else { return }
            
            L.og.debug("😎 ImposterChecker similar name: \(contactAnyName) - \(similarFollow.anyName)")
            
            Task.detached(priority: .background) {
                let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                guard similarPFP else { return }
                L.og.debug("😎 ImposterChecker similar PFP: \(cPic) - \(wotPic) - \(cPubkey)")
                DispatchQueue.main.async {
                    guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                    
                    let couldBeImposter: Int16 = similarPFP ? 1 : 0
                    nrContact.couldBeImposter = couldBeImposter
                    
                    let similarToPubkey = similarPFP ? followingPubkey : nil
                    nrContact.similarToPubkey = similarToPubkey
                    
                    completion(CouldBeImposterYes(similarToPubkey: followingPubkey))
                    
                    bg().perform {
                        nrContact.contact?.couldBeImposter = couldBeImposter
                        nrContact.contact?.similarToPubkey = similarToPubkey
                    }
                }
            }
        }
    }
    
    private func shouldRunCheck(nrContact: NRContact) -> Bool {
        guard !SettingsStore.shared.lowDataMode else { return false }
        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return false }
        guard !isFollowing(nrContact.pubkey) else { return false }
        guard nrContact.metadata_created_at != 0 else { return false }
        guard nrContact.couldBeImposter == -1 else { return false }
        guard !NewOnboardingTracker.shared.isOnboarding else { return false }
        return true
    }
    
    private func shouldRunCheck(contact: Contact) -> Bool {
        guard !SettingsStore.shared.lowDataMode else { return false }
        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return false }
        guard !isFollowing(contact.pubkey) else { return false }
        guard contact.metadata_created_at != 0 else { return false }
        guard contact.couldBeImposter == -1 else { return false }
        guard !NewOnboardingTracker.shared.isOnboarding else { return false }
        return true
    }
}


struct CouldBeImposterYes {
    var similarToPubkey: String
}
