//
//  VoiceMessagesTests.swift
//  NosturTests
//
//  Created by Fabian Lachman on 01/08/2025.
//

import Testing
import Foundation
@testable import FFmpegSupport

struct VoiceMessagesTests {

    @Test func testWebmToM4a() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        
        let input = URL(fileURLWithPath: "/Users/fabian/Development/tmp/test-opus.webm")
        let output = URL(fileURLWithPath: "/Users/fabian/Development/tmp/test-opus.m4a")
        
        for _ in 1..<2 {
            _ = ffmpeg([
                "ffmpeg",
//                "-bsfs"
                "-y",
                "-i", input.path,
                output.path
            ])
        }
    }
    
    

}
