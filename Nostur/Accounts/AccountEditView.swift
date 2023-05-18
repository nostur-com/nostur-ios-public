//
//  AccountView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/01/2023.
//

import SwiftUI
import CoreData
import Combine
import Nuke
import NukeUI
import CryptoKit

struct AccountEditView: View {
    
    var sp:SocketPool = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    let up:Unpublisher = .shared
    @EnvironmentObject var ns:NosturState
    @ObservedObject var account: Account
    @State var newPrivateKey = ""
    @State var contactsPresented = false
    @State var invalidPrivateKey = false
    @State var uploading = false
    @State var uploadError:String?
    @State var subscriptions = Set<AnyCancellable>()
    @State var newPicture:UIImage?
    @State var newBanner:UIImage?
    
    var body: some View {
        let shouldDisable = account.privateKey == nil || account.privateKey == ""
        GeometryReader { geo in
            VStack {
                ZStack {
                    BannerPicPicker($account.banner, newPicture:$newBanner, width: geo.size.width)
                        .frame(height: 150)
                        .clipped()
                    HStack {
                        ProfilePicPicker($account.picture, newPicture:$newPicture)
                            .offset(x: 20, y: 60)
                        Spacer()
                    }
                }
                .listRowBackground(Color(.systemGroupedBackground))
                ZStack {
                    Form {
                        
                        Group {
                            Section(header: Text("Your name") ) {
                                TextField("Enter your name", text: $account.display_name).disabled(shouldDisable)
                                    .disableAutocorrection(true)
                            }
                            
                            Section(header: Text("Your username") ) {
                                TextField("Enter your username", text: $account.name).disabled(shouldDisable)
                                    .keyboardType(.URL)
                                    .disableAutocorrection(true)
                                    .textInputAutocapitalization(.never)
                            }
                            
                            Section(header: Text("Bio") ) {
                                TextField("Something about yourself", text:$account.about, axis: .vertical)
                                    .lineLimit(3...5)
                                    .disabled(shouldDisable)
                            }
                            
                            Section(header: Text("NIP-05 identifier") ) {
                                TextField("", text: $account.nip05).keyboardType(.emailAddress).disabled(shouldDisable)
                                    .keyboardType(.URL)
                                    .disableAutocorrection(true)
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        //                    .listRowInsets(EdgeInsets())
                        
                        Section(header: Text("Lightning Address (LUD-16)") ) {
                            TextField("", text: $account.lud16).keyboardType(.emailAddress).disabled(shouldDisable)
                                .keyboardType(.URL)
                                .disableAutocorrection(true)
                                .textInputAutocapitalization(.never)
                        }
                        
                        Section(header: Text("Lightning Address (LUD-06)") ) {
                            TextField("", text: $account.lud06).keyboardType(.URL).disabled(shouldDisable)
                                .keyboardType(.URL)
                                .disableAutocorrection(true)
                                .textInputAutocapitalization(.never)
                        }
                        
                        if (newPicture == nil) {
                            Section(header: Text("Profile picture URL") ) {
                                TextField("https://nostur.com/profile.jpg", text: $account.picture).keyboardType(.URL).disabled(shouldDisable)
                                    .keyboardType(.URL)
                                    .disableAutocorrection(true)
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        
                        if (newBanner == nil) {
                            Section(header: Text("Profile banner URL") ) {
                                TextField("https://nostur.com/banner.jpg", text: $account.banner).keyboardType(.URL).disabled(shouldDisable)
                                    .keyboardType(.URL)
                                    .disableAutocorrection(true)
                                    .textInputAutocapitalization(.never)
                            }
                        }
                        
                        if (shouldDisable) {
                            Section(header:Text("Import private key")) {
                                TextField("nsec1...", text: $newPrivateKey).foregroundColor(.primary)
                                    .keyboardType(.URL)
                                    .disableAutocorrection(true)
                                    .textInputAutocapitalization(.never)
                            }.foregroundColor(.primary)
                        }
                        
                        Section(header: Text(shouldDisable ? "Public key" : "Keys") ) {
                            HStack {
                                Text("**PUBLIC KEY:** \(account.npub)").lineLimit(1)
                                Image(systemName: "doc.on.doc.fill")
                                    .onTapGesture {
                                        UIPasteboard.general.string = account.npub
                                        sendNotification(.anyStatus, ("Public key copied to clipboard", "COPYKEYS"))
                                    }
                            }
                            
                            if (!shouldDisable && account.nsec != nil) {
                                HStack {
                                    Text("**PRIVATE KEY:** \(String(account.nsec!.prefix(7)))∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗∗").lineLimit(1)
                                    Spacer()
                                    Image(systemName: "doc.on.doc.fill")
                                        .onTapGesture {
                                            UIPasteboard.general.string = account.nsec!
                                            sendNotification(.anyStatus, ("Private key copied to clipboard", "COPYKEYS"))
                                        }
                                }
                            }
                        }
                    }
                    .foregroundColor(shouldDisable ? .gray : .primary)
                    .padding(.top, 20)
                    
                    VStack {
                        Spacer()
                        AnyStatus(filter: "COPYKEYS")
                            .opacity(0.85)
                    }
                    //            Button {
                    //                updateContacts()
                    //            } label: {
                    //                Text("Update contacts metadata")
                    //            }
                    //            Button {
                    //                loadFollowers(account: account)
                    //            } label: {
                    //                Text("load followers from kind 3")
                    //            }
                }
                Button {
                    loadFromRelays()
                } label: {
                    Text("Load info and contacts from relays")
                        .foregroundColor(Color.primary)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(Color.primary)
            }
            
            if let uploadError {
                ToolbarItem(placement: .principal) {
                    Text(uploadError).foregroundColor(.red)
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if newPicture != nil || newBanner != nil {
                        uploading = true
                        uploadBannerOrProfilePic(pfp: newPicture, banner: newBanner)
                            .receive(on: RunLoop.main)
                            .sink(receiveCompletion: { result in
                                switch result {
                                    case .failure(let error):
                                        print("Error uploading images: \(error.localizedDescription)")
                                        uploadError = "Image upload error"
                                        sendNotification(.anyStatus, ("Upload error: \(error.localizedDescription)", "NewPost"))
                                        uploading = false
                                    case .finished:
                                        print("PFP uploaded successfully")
                                }
                            }, receiveValue: { urls in
                                print(urls)
                                for url in urls {
                                    if url.contains("/banner.") {
                                        account.banner = url
                                    }
                                    if url.contains("/profilepic.") {
                                        account.picture = url
                                    }
                                }
                                save()
                                uploading = false
                            })
                            .store(in: &subscriptions)
                    }
                    else {
                        save()
                    }
                } label: {
                    if uploading {
                        ProgressView()
                    }
                    else {
                        Text("Save")
                            .foregroundColor(Color.primary)
                    }
                }
                .disabled(uploading)
            }
        }
        .alert("Invalid private key", isPresented: $invalidPrivateKey) {
            Button("OK", role: .cancel) { }
        }
        .onAppear {
            if (account.privateKey == nil) {
                let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: account.publicKey))
                sp.sendMessage(message)
            }
        }
    }
}

extension AccountEditView {
    
    func save() {
        if newPrivateKey != "" {
            
            guard let nip19 = try? NIP19(displayString: newPrivateKey) else {
                invalidPrivateKey = true
                newPrivateKey = ""
                return
            }
            guard let keys = try? NKeys(privateKeyHex: nip19.hexString) else {
                invalidPrivateKey = true
                newPrivateKey = ""
                return
            }
            
            guard (keys.publicKeyHex() == account.publicKey) else {
                invalidPrivateKey = true
                newPrivateKey = ""
                return
            }
            
            account.privateKey = keys.privateKeyHex()
        }
        do {
            try publishMetadataEvent()
            dismiss()
        }
        catch {
            print("Error saving account")
        }
    }
    
    func publishMetadataEvent() throws {
        guard account.privateKey != nil else {
            throw "Account has no private key"
        }
        
        // create nostr .setMetadata event
        var setMetadataContent = NSetMetadata(name: account.name, about: account.about, picture: account.picture)
        if account.nip05 != "" { setMetadataContent.nip05 = account.nip05 }
        if account.lud16 != "" { setMetadataContent.lud16 = account.lud16 }
        if account.lud06 != "" { setMetadataContent.lud06 = account.lud06 }
        if account.banner != "" { setMetadataContent.banner = account.banner }
        if account.display_name != "" { setMetadataContent.display_name = account.display_name }
        
        if (account.privateKey != nil) {
            do {
                let keys = try NKeys(privateKeyHex: account.privateKey!)
                
                var newKind0Event = NEvent(content: setMetadataContent)
                
                let newKind0EventSigned = try newKind0Event.sign(keys)
                
                print(newKind0EventSigned.eventJson())
                print(newKind0EventSigned.wrappedEventJson())
                
                
                _ = Event.saveEventFromMain(event: newKind0EventSigned)
                Contact.saveOrUpdateContact(event: newKind0EventSigned)
                DataProvider.shared().bgSave()
                // broadcast to relays
                up.publishNow(newKind0EventSigned)
            }
            catch {
                print("🔴🔴🔴🔴 Could not sign/save/broadcast event 🔴🔴🔴🔴")
            }
        }
    }
    
    func loadFromRelays() {
        // 1. Prefill from cached event (if in cache)
        Account.preFillReadOnlyAccountInfo(account: account, context: viewContext, forceOverwrite: true)
        Account.preFillReadOnlyAccountFollowing(account: account, context: viewContext)
                
        let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndContactList(pubkey: account.publicKey))
        
        sp.sendMessage(message)
    }

    func loadFollowers(account:Account) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@", account.publicKey)
        let clEvent = try! viewContext.fetch(fr).first
        if (clEvent != nil) {
            
            let contactPubkeys = TagsHelpers(clEvent?.tags() ?? []).pTags().map { $0.pubkey }
            
            let cr = Contact.fetchRequest()
            cr.predicate = NSPredicate(format: "pubkey IN %@", contactPubkeys)
            let contacts = try! viewContext.fetch(cr)
            
            for contact in contacts {
                account.addToFollows(contact)
                print("Adding to followers: \(contact.name ?? "??")")
            }
            try! viewContext.save();
        }
    }
    
    func updateContacts() { // move this method to somewhere more global maybe
        let pubkeys = account.follows?.map { $0.pubkey }
        if (pubkeys != nil) {
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys!)))
        }
    }
}


struct AccountView_Previews: PreviewProvider {
    static var previews: some View {
        
        let fab = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
//        let other = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        
            NavigationStack {
                if let account = PreviewFetcher.fetchAccount(fab, context: DataProvider.shared().container.viewContext) {
                    AccountEditView(account: account)
                }
                    
            }
            .withPreviewEnvironment()
    }
}

func uploadBannerOrProfilePic(pfp: UIImage?, banner:UIImage?) -> AnyPublisher<[String], Error> {
    var imagePublishers:[AnyPublisher<String, Error>] = []
    
    if let pfp {
        imagePublishers.append( uploadPFPImage(image: pfp) )
    }
    
    if let banner {
        imagePublishers.append( uploadBannerImage(image: banner) )
    }
    return Publishers.MergeMany(imagePublishers)
        .collect()
        .eraseToAnyPublisher()
}


func uploadPFPImage(image: UIImage) -> AnyPublisher<String, Error> {

    // Create a profile pic, preserving aspect ratio, resize to 150x150

    let SIDE:CGFloat = 150
    let size = CGSize(width: SIDE, height: SIDE)
//    let rect = CGRect(origin: CGPoint.zero, size: size)
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    
    // Steps.
    // Take smallest of width or height
    // if below 100, upscale to 100
    if image.size.width < image.size.height && image.size.width < SIDE {
        // WIDTH IS TOO SMALL:
        let upscaleFactor = SIDE / image.size.width
        let newHeight = image.size.height * upscaleFactor
        let x = 0.0
        let y = -((newHeight-SIDE)/2).rounded(.down)
        let drawRect = CGRect(x: x, y: y, width: SIDE, height: newHeight)
        image.draw(in: drawRect)
    }
    else if image.size.height < image.size.width && image.size.height < SIDE {
        // HEIGHT IS TOO SMALL:
        let upscaleFactor = SIDE / image.size.height
        let newWidth = image.size.width * upscaleFactor
        let x = -((newWidth-SIDE)/2).rounded(.down)
        let y = 0.0
        let drawRect = CGRect(x: x, y: y, width: newWidth, height: SIDE)
        image.draw(in: drawRect)
    }
    else if image.size.width < image.size.height && image.size.width > SIDE {
        // WIDTH SMALLER THAN HEIGHT, BUT TOO BIG
        let downscaleFactor = image.size.width / SIDE
        let newHeight = image.size.height / downscaleFactor
        let x = 0.0
        let y = -((newHeight-SIDE)/2).rounded(.down)
        let drawRect = CGRect(x: x, y: y, width: SIDE, height: newHeight)
        image.draw(in: drawRect)
    }
    else if image.size.height < image.size.width && image.size.height > SIDE {
        // HEIGHT SMALLER THAN WIDTH, BUT TOO BIG
        let downscaleFactor = image.size.height / SIDE
        let newWidth = image.size.width / downscaleFactor
        let x = -((newWidth-SIDE)/2).rounded(.down)
        let y = 0.0
        let drawRect = CGRect(x: x, y: y, width: newWidth, height: SIDE)
        image.draw(in: drawRect)
    }
    else {
//        let aspect = image.size.width / image.size.height
        let x = 0.0
        let y = 0.0
        let width = SIDE
        let height = SIDE
        let drawRect = CGRect(x: x, y: y, width: width, height: height)
        image.draw(in: drawRect)
    }
    
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
        
    guard let imageData = scaledImage?.jpegData(compressionQuality: 0.8) else {
        return Fail(error: ImageUploadError.conversionFailure).eraseToAnyPublisher()
    }
    
    let url = URL(string: "https://nostur.com/upload2.php")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    
    let boundary = UUID().uuidString
    let contentType = "multipart/form-data; boundary=\(boundary)"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    
    guard let proof = signedImageProof(imageData: imageData) else { return Fail(error: ImageUploadError.signingFailure).eraseToAnyPublisher() }
    request.setValue(proof.signature, forHTTPHeaderField: "X-Nostur-Signature")
    request.setValue(proof.message, forHTTPHeaderField: "X-Nostur-Message")
    request.setValue(proof.publicKey, forHTTPHeaderField: "X-Nostur-PublicKey")
    
    let body = NSMutableData()
    let fieldName = "image"
    
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(imageData)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    
    request.httpBody = body as Data
    
    let session = URLSession(configuration: .default)
    return session.dataTaskPublisher(for: request)
        .tryMap { data, response -> String in
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let link = json["data"] as? [String: Any],
                  let url = link["link"] as? String else {
//                let httpResponse = response as? HTTPURLResponse
//                print(httpResponse?.statusCode)
//                print(httpResponse?.allHeaderFields)
//                let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
//                print(json?.description)
                throw ImageUploadError.uploadFailure
            }
            return url
        }
        .eraseToAnyPublisher()
}

// Scales an image to fit within a given height and width
// Preserves aspect ratio
// Fills the entire space, cropping if necessary
func scaleImageToFill(image: UIImage, height: CGFloat, width: CGFloat) -> UIImage? {
    let size = image.size
    let widthRatio = width / size.width
    let heightRatio = height / size.height
    let scaleRatio = max(widthRatio, heightRatio)
    let scaledSize = CGSize(width: (size.width * scaleRatio).rounded(.down), height: (size.height * scaleRatio).rounded(.down))
    let origin = CGPoint(x: (width - scaledSize.width) / 2, y: (height - scaledSize.height) / 2)
    UIGraphicsBeginImageContextWithOptions(CGSize(width: width.rounded(.down), height: height.rounded(.down)), false, 0)
    image.draw(in: CGRect(origin: origin, size: scaledSize))
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return scaledImage
}

//
//func scaleImageToFill(image: UIImage, maxHeight: CGFloat, maxWidth: CGFloat) -> UIImage? {
//    let imageSize = image.size
//    let aspectRatio = imageSize.width / imageSize.height
//    let maxAspectRatio = maxWidth / maxHeight
//    var scale: CGFloat
//    var cropRect = CGRect.zero
//
//    if aspectRatio > maxAspectRatio {
//        scale = maxWidth / imageSize.width
//        let height = imageSize.height * scale
//        cropRect = CGRect(x: 0, y: (maxHeight - height) / 2.0, width: maxWidth, height: height)
//    } else {
//        scale = maxHeight / imageSize.height
//        let width = imageSize.width * scale
//        cropRect = CGRect(x: (maxWidth - width) / 2.0, y: 0, width: width, height: maxHeight)
//    }
//
//    UIGraphicsBeginImageContextWithOptions(CGSize(width: maxWidth, height: maxHeight), false, UIScreen.main.scale)
//    defer { UIGraphicsEndImageContext() }
//
//    image.draw(in: cropRect)
//
//    guard let scaledImage = UIGraphicsGetImageFromCurrentImageContext() else {
//        return nil
//    }
//
//    return scaledImage
//}

func uploadBannerImage(image: UIImage) -> AnyPublisher<String, Error> {
    
    guard let scaledImage = scaleImageToFill(image: image, height: 150, width: 600) else {
        return Fail(error: ImageUploadError.scalingFailure).eraseToAnyPublisher()
    }
    
//    let scaledImage = scaleImageToFill(image: image, height: 300, width: 900)
    
    guard let imageData = scaledImage.jpegData(compressionQuality: 0.8) else {
        return Fail(error: ImageUploadError.conversionFailure).eraseToAnyPublisher()
    }
    
    let url = URL(string: "https://nostur.com/uploadbanner2.php")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    
    let boundary = UUID().uuidString
    let contentType = "multipart/form-data; boundary=\(boundary)"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    
    guard let proof = signedImageProof(imageData: imageData) else { return Fail(error: ImageUploadError.signingFailure).eraseToAnyPublisher() }
    request.setValue(proof.signature, forHTTPHeaderField: "X-Nostur-Signature")
    request.setValue(proof.message, forHTTPHeaderField: "X-Nostur-Message")
    request.setValue(proof.publicKey, forHTTPHeaderField: "X-Nostur-PublicKey")
    
    let body = NSMutableData()
    let fieldName = "image"
    
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(imageData)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    
    request.httpBody = body as Data
    
    let session = URLSession(configuration: .default)
    return session.dataTaskPublisher(for: request)
        .tryMap { data, response -> String in
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let link = json["data"] as? [String: Any],
                  let url = link["link"] as? String else {
//                let httpResponse = response as? HTTPURLResponse
//                print(httpResponse?.statusCode)
//                print(httpResponse?.allHeaderFields)
//                let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
//                print(json?.description)
                throw ImageUploadError.uploadFailure
            }
            return url
        }
        .eraseToAnyPublisher()
}


func signedImageProof(imageData:Data) -> (signature: String, message: String, publicKey: String)? {
    guard let privateKeyHexString = NosturState.shared.account?.privateKey else { return nil }
    guard let nostrPubkeyHex = NosturState.shared.account?.publicKey else { return nil }
    
    // NO EASY WAY TO VERIFY SCHNORR SIG IN PHP, SO JUST USE CRYPTOGRAPHY THAT JUST WORKS OUT OF THE BOX:
    // SECURITY SHOULD BE THE SAME, YOU CAN ONLY REPLACE THE PROFILE PIC IF YOU HAVE THE PRIVATE KEY
    // DOESNT MATTER IF THE SIGNATURE IS SCHNORR OR Curve25519
    
    // TODO: EVENTALLY REPLACE WITH NOSTR SCHNORR VERIFICATION WHEN THERE IS PROPER PHP SUPPORT SO WE DONT HAVE TO DERRIVE AN EXTRA KEY
    
    guard let privateKeyData = Data(fromHexEncodedString: privateKeyHexString) else { return nil }
    // Create a SymmetricKey from the Schnorr private key data
    let symmetricKey = SymmetricKey(data: privateKeyData)

    
    // Use HKDF to derive a Curve25519 private key
    let info = "Curve25519 private key".data(using: .utf8)!
    let salt = "Salty " + nostrPubkeyHex
    guard let saltData = salt.data(using: .utf8) else { return nil }

    let derivedKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: symmetricKey, salt: saltData, info: info, outputByteCount: 32)

    guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: derivedKey) else { return nil }
//    guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) else { return nil }

    let publicKey = privateKey.publicKey
    let publicKeyData = publicKey.rawRepresentation
    let publicKeyHexString = publicKeyData.map { String(format: "%02hhx", $0) }.joined()
    
    
    let sha256data = SHA256.hash(data: imageData)
    let sha256string = String(bytes:sha256data.bytes)

    let message = "\(Int64(Date().timeIntervalSince1970).description)|\(sha256string)"
    let messageData = message.data(using: .utf8)!

    let signature = try! privateKey.signature(for: messageData)
    let signatureHexString = signature.map { String(format: "%02hhx", $0) }.joined()

    // Send `signatureHexString`, `message`, and `publicKeyHexString` to the server

    return (signature: signatureHexString, message: message, publicKey: publicKeyHexString)
}


// same as signedImageProof but without imageData, we just hash of the word DELETE
func signedDeleteProof(pk privateKeyHexString:String, pubkey nostrPubkeyHex:String) -> (signature: String, message: String, publicKey: String)? {
    
    // NO EASY WAY TO VERIFY SCHNORR SIG IN PHP, SO JUST USE CRYPTOGRAPHY THAT JUST WORKS OUT OF THE BOX:
    // SECURITY SHOULD BE THE SAME, YOU CAN ONLY REPLACE THE PROFILE PIC IF YOU HAVE THE PRIVATE KEY
    // DOESNT MATTER IF THE SIGNATURE IS SCHNORR OR Curve25519
    
    // TODO: EVENTALLY REPLACE WITH NOSTR SCHNORR VERIFICATION WHEN THERE IS PROPER PHP SUPPORT SO WE DONT HAVE TO DERRIVE AN EXTRA KEY
    
    guard let privateKeyData = Data(fromHexEncodedString: privateKeyHexString) else { return nil }
    // Create a SymmetricKey from the Schnorr private key data
    let symmetricKey = SymmetricKey(data: privateKeyData)

    
    // Use HKDF to derive a Curve25519 private key
    let info = "Curve25519 private key".data(using: .utf8)!
    let salt = "Salty " + nostrPubkeyHex
    guard let saltData = salt.data(using: .utf8) else { return nil }

    let derivedKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: symmetricKey, salt: saltData, info: info, outputByteCount: 32)

    guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: derivedKey) else { return nil }
//    guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) else { return nil }

    let publicKey = privateKey.publicKey
    let publicKeyData = publicKey.rawRepresentation
    let publicKeyHexString = publicKeyData.map { String(format: "%02hhx", $0) }.joined()
    
    
    let sha256data = SHA256.hash(data: "DELETE".data(using: .utf8)!)
    let sha256string = String(bytes:sha256data.bytes)

    let message = "\(Int64(Date().timeIntervalSince1970).description)|\(sha256string)"
    let messageData = message.data(using: .utf8)!

    let signature = try! privateKey.signature(for: messageData)
    let signatureHexString = signature.map { String(format: "%02hhx", $0) }.joined()

    // Send `signatureHexString`, `message`, and `publicKeyHexString` to the server

    return (signature: signatureHexString, message: message, publicKey: publicKeyHexString)
}
