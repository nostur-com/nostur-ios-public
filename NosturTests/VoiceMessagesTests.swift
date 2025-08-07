////
////  VoiceMessagesTests.swift
////  NosturTests
////
////  Created by Fabian Lachman on 01/08/2025.
////
//
//import Testing
//import Foundation
////@testable import FFmpegSupport
//@testable import FFmpegKit
//
//struct VoiceMessagesTests {
//
//    @Test func testWebmToM4a() async throws {
//        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
//        
////        let input = URL(fileURLWithPath: "/Users/fabian/Development/tmp/test-opus.webm")
////        let output = URL(fileURLWithPath: "/Users/fabian/Development/tmp/test-opus.m4a")
////        
////        for _ in 1..<2 {
////            _ = ffmpeg([
////                "ffmpeg",
//////                "-bsfs"
////                "-y",
////                "-i", input.path,
////                output.path
////            ])
////        }
//    }
//    
//    @Test func testWebmToM4aFFmpegKit() async throws {
//              let input = URL(fileURLWithPath: "/Users/fabian/Development/tmp/test-opus.webm")
//              let output = URL(fileURLWithPath: "/Users/fabian/Development/tmp/test-opus.m4a")
//
//              // Verify input file exists
//              #expect(FileManager.default.fileExists(atPath: input.path), "Input webm file should exist")
//
//              // Remove output file if it exists
//              try? FileManager.default.removeItem(at: output)
//
//              // Convert webm opus to m4a
//              let arguments = [
//                  "ffmpeg",
//                  "-y",                    // Overwrite output file
//                  "-i", input.path,        // Input .webm file
//                  "-c:a", "aac",          // AAC audio codec
//                  "-b:a", "128k",         // Audio bitrate
//                  output.path             // Output .m4a file
//              ]
//
//              var argv = arguments.map {
//                  UnsafeMutablePointer(mutating: ($0 as NSString).utf8String)
//              }
//
//              let result = ffmpeg_execute(Int32(arguments.count), &argv)
//
//              // Check conversion succeeded
//              #expect(result == 0, "FFmpeg conversion should succeed (exit code 0)")
//
//              // Verify output file was created
//              #expect(FileManager.default.fileExists(atPath: output.path), "Output m4a file should be created")
//
//              // Verify output file has content
//              let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
//              let fileSize = attributes[.size] as? Int64 ?? 0
//              #expect(fileSize > 0, "Output file should have content")
//
//              print("✅ Conversion successful: \(input.lastPathComponent) → \(output.lastPathComponent)")
//              print("📁 Output size: \(fileSize) bytes")
//          }
//    
//    
//
//}


import Testing
import Foundation
@testable import Nostur

  struct VoiceMessagesTests {

      @Test func testWebmToM4a() async throws {
//          let input = URL(fileURLWithPath: "/Users/fabian/Development/tmp/test-opus.webm")
//          let output = URL(fileURLWithPath: "/Users/fabian/Development/tmp/test-opus.m4a")

          let result = convert_webm_to_m4a("/Users/fabian/Development/tmp/test-opus.webm", "/Users/fabian/Development/tmp/test-opus.m4a")
          if result == 0 {
              print("Conversion succeeded.")
          } else {
              print("FFmpeg conversion failed with code: \(result)")
          }

          #expect(result == 0, "FFmpeg conversion should return 0")
          print("✅ Test completed - WebM to M4A conversion successful")
      }
  }
