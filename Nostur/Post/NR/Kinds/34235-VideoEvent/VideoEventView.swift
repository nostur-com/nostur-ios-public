//
//  VideoEventView.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/12/2023.
//

import SwiftUI
import NukeUI

struct VideoEventView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.availableWidth) private var availableWidth
    
    public let title: String
    public let url: URL
    
    public var summary: String?
    public var imageUrl: URL?
    public var thumb: String?
    
    public var autoload: Bool = false
    
    static let aspect: CGFloat = 16/9
    
    var body: some View {
        if autoload {
            Group {
                VStack(alignment: .leading, spacing: 5) {
                    if let imageUrl {
                        MediaContentView(
                            galleryItem: GalleryItem(url: imageUrl),
                            availableWidth: availableWidth,
                            placeholderAspect: 16/9,
                            maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                            contentMode: .fit,
                            autoload: autoload
//                            tapUrl: url
                        )
                    }
                    else {
                        Image(systemName: "movieclapper")
                            .resizable()
                            .scaledToFit()
                            .padding()
                            .foregroundColor(Color.gray)
                            .frame(width: DIMENSIONS.PREVIEW_HEIGHT * Self.aspect)
                            .onTapGesture {
                                openURL(url)
                            }
                    }
                    if #available(iOS 16.0, *) {
                        Text(title)
                            .lineLimit(2)
                            .layoutPriority(1)
                            .fontWeight(.bold)
                            .padding(5)
                    }
                    else {
                        Text(title)
                            .lineLimit(2)
                            .layoutPriority(1)
                            .padding(5)
                    }
                    
                    if let summary, !summary.isEmpty {
                        Text(summary)
                            .lineLimit(30)
                            .font(.caption)
                            .padding(5)
                    }
                    
                    Text(url.absoluteString)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(5)
//                            .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(theme.listBackground)
            }
            .onTapGesture {
                openURL(url)
            }
        }
        else {
            Text(url.absoluteString)
                .foregroundColor(theme.accent)
                .truncationMode(.middle)
                .onTapGesture {
                    openURL(url)
                }
        }
    }
}


#Preview("Vine") {
    PreviewContainer({ pe in
        
    }) {
        PostOrThread(
            nrPost: testNRPost(###"{"id":"82bb357dc59d3361bbf6ff768513e8f5e4eed5504ab6656c4c3c665618765266","pubkey":"7306f0459d42ed3b50926256710beb8ef031a80b659aa9ae819ec4fab4bd8812","created_at":1763330209,"kind":34236,"tags":[["d","684ee62db8db6347a4a1ef27a23c363f1129a65efa4930d8f7e17a4be3b4b5b1"],["imeta","url https://cdn.divine.video/684ee62db8db6347a4a1ef27a23c363f1129a65efa4930d8f7e17a4be3b4b5b1.mp4","m video/mp4","image https://cdn.divine.video/bcd371cc9bb42efaab5cdb5afd70b90523043924652a02a5347ae8f894706c83.jpg","size 1070110","x 684ee62db8db6347a4a1ef27a23c363f1129a65efa4930d8f7e17a4be3b4b5b1","blurhash LEE_,9WANGjY}=NKRkazENn$oeWB"],["title","70s bathroom"],["summary","🤔"],["t","vine"],["t","nostr"],["client","openvine"],["published_at","1763330239"],["duration","3"],["alt","70s bathroom"],["verification","verified_web"],["proofmode","{\"videoHash\":\"684ee62db8db6347a4a1ef27a23c363f1129a65efa4930d8f7e17a4be3b4b5b1\",\"pgpSignature\":\"-----BEGIN PGP SIGNATURE-----\\nVersion: BCPG v1.71\\n\\niQIcBAABCAAGBQJpGkh4AAoJEGJlPhmNpi91J3MP/jGMnOE8IsjV6fx4uJ2sKxjm\\n4yXcSfnkukMqX0tJu5tnz02LS0UveFDq21y5S8Ffea0pZmX4bLa6YlgzahSunfoU\\nWN4E0ukfLa46HpfXnz4h9+xvMfsFCW8MuvW3kRtG9BhHiZvFXCQFHmkWbnuMdAIC\\nVPKpeZxB7VUTV2dN1O4ErBgN1ylPzuSzwk12+6fJ7PEi4lGnLYBhWC1BROYVsWqh\\nse3AFisRTUsth3OAwGGITmysq3mn9zsQrLdrR553vx9OO3HZwzZOjrjWTZONfEgj\\nGWgI8lXE4ros60Fdyk4xOYY8ibPgIrpmZgHkIekhVmxq1BDuW1kIClHZJ+E9+JPc\\n48H71cliGJlfK4PBgeNtS2fL1WIWkPE6i7qqRk2+OClvZ8kH2YJt/zAW43sU3guQ\\nP7DVv/S3M8pOVLEEbiD9KLhIlsH3izBr1pV8T9i+K54W5IJyflvzX4pQEv6Ig6Sb\\ngHk8kz4Nx6sXsDRQXFTbryLruahR9UzRBYL2pR4n5YroJ8hG+yQ150XCGuZ4MnKB\\n7pqbrn/zT2mJDVa1CkNKCeFZydAZk9J0VWMNVk3mSXffiwv4VQnBMjHmooUWKeic\\nnpgR53qcCWbIizipud+2MyKzfDZ96iBqAq6DaEJR2w0CiLLgzPmZnGHX7MkxYzWI\\ngAOwdQcsl0blct3j0+VY\\n=6Oo/\\n-----END PGP SIGNATURE-----\\n\"}"]],"content":"🤔","sig":"217d837c4c9e4c1112c65b3b50e9cd1407d3e85936c4891d4459a4c85b366b874c7bd9f3c082e8d374fe4cc661836f6f276c115842146fdbdcda48255872a839"}"###),
            theme: Themes.default.theme)
    }
}

#Preview("Vine 2") {
    PreviewContainer({ pe in
        
    }) {
        PostOrThread(
            nrPost: testNRPost(###"{"kind":34236,"id":"26eff0b456d3f9b0030f6897aa0f23c5fc7f52301e468d836c6c3347f3f805f0","tags":[["d","97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7"],["imeta","url https://cdn.divine.video/97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7.mp4","url https://stream.divine.video/678778b3-b8a3-4a57-ac34-6f046907aab0/playlist.m3u8","m video/mp4","image https://stream.divine.video/678778b3-b8a3-4a57-ac34-6f046907aab0/thumbnail.jpg","size 1001958","x 97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7","blurhash LjGRPYbDM_xZ0gxZxrWY$ut7bJRn"],["title",""],["summary",""],["client","openvine"],["published_at","1763406697"],["duration","6"],["alt",""]],"sig":"de5345eda729e1c52ef38685440f2e52812c05216723c9227e811764766e741b0e621b86359879278a7bcfdefde906349c0311000702cd132cd5dcde85215b89","created_at":1763406667,"content":"","pubkey":"a0e998aaf688a5ee796384212681c670446c430fd60bf9e942606d68ab564324"}"###),
            theme: Themes.default.theme)
    }
}




@available(iOS 26.0, *)
#Preview("Vine 3") {
    @Previewable @Environment(\.theme) var theme
    @Previewable @State var nrPost = testNRPost(###"{"kind":34236,"id":"26eff0b456d3f9b0030f6897aa0f23c5fc7f52301e468d836c6c3347f3f805f0","tags":[["d","97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7"],["imeta","url https://cdn.divine.video/97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7.mp4","url https://stream.divine.video/678778b3-b8a3-4a57-ac34-6f046907aab0/playlist.m3u8","m video/mp4","image https://stream.divine.video/678778b3-b8a3-4a57-ac34-6f046907aab0/thumbnail.jpg","size 1001958","x 97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7","blurhash LjGRPYbDM_xZ0gxZxrWY$ut7bJRn"],["title",""],["summary",""],["client","openvine"],["published_at","1763406697"],["duration","6"],["alt",""]],"sig":"de5345eda729e1c52ef38685440f2e52812c05216723c9227e811764766e741b0e621b86359879278a7bcfdefde906349c0311000702cd132cd5dcde85215b89","created_at":1763406667,"content":"","pubkey":"a0e998aaf688a5ee796384212681c670446c430fd60bf9e942606d68ab564324"}"###)
    PreviewContainer({ pe in
        
    }) {
        PreviewApp {
            ScrollView {
                LazyVStack {
//                    Color.random
//                        .frame(height: 400)
                    
                    VideoPost(nrPost: nrPost, theme: theme)
//                    Color.random
//                        .frame(height: 400)
//
//                    Color.random
//                        .frame(height: 400)
                }
            }
        }
    }
}
