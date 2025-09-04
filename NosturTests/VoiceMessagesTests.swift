//
//  VoiceMessagesTests.swift
//  NosturTests
//
//  Created by Fabian Lachman on 01/08/2025.
//

import Foundation
import Testing
@testable import Nostur
import AVFoundation
import CoreMedia

struct VoiceMessagesTests {

    @Test func testWebmToM4a() async throws {
        let bundle = Bundle(for: TestBundleLocator.self)
        
        guard
            let inputURL = bundle.url(
                forResource: "test-opus",
                withExtension: "webm"
            )
        else {
            Issue.record("Missing test resource")
            return
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-opus.m4a")

        let result = convert_webm_to_m4a(inputURL.path, outputURL.path)
        if result == 0 {
            print("Conversion succeeded. Output: \(outputURL.path)")
        } else {
            print("FFmpeg conversion failed with code: \(result)")
        }

        #expect(result == 0, "FFmpeg conversion should return 0")
        print("✅ Test completed - WebM to M4A conversion successful")
    }
    
    @Test func testIdentifyFileType() async throws {
        let bundle = Bundle(for: TestBundleLocator.self)
        guard
            let inputURL = bundle.url(
                forResource: "b14f3c5d9a0f8ca838ea32c63b32e84a94b5b34235e51ba07476d8b3e5ddd569",
                withExtension: nil
            )
        else {
            Issue.record("Missing test resource")
            return
        }
        
        
        let audioFile = try AVAudioFile(forReading: inputURL)
        print("audioFile processingFormat:", audioFile.fileFormat.formatDescription.mediaSubType)

        #expect(detectAudioFormat(inputURL) == .opus)

    }
}

private class TestBundleLocator {}
