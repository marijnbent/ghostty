//
//  NSPasteboardTests.swift
//  GhosttyTests
//
//  Tests for NSPasteboard.PasteboardType MIME type conversion.
//

import Testing
import AppKit
@testable import Ghostty

struct NSPasteboardTypeExtensionTests {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: .init("test-\(UUID().uuidString)"))
    }

    /// Test text/plain MIME type converts to .string
    @Test func testTextPlainMimeType() async throws {
        let pasteboardType = NSPasteboard.PasteboardType(mimeType: "text/plain")
        #expect(pasteboardType != nil)
        #expect(pasteboardType == .string)
    }

    /// Test text/html MIME type converts to .html
    @Test func testTextHtmlMimeType() async throws {
        let pasteboardType = NSPasteboard.PasteboardType(mimeType: "text/html")
        #expect(pasteboardType != nil)
        #expect(pasteboardType == .html)
    }

    /// Test image/png MIME type
    @Test func testImagePngMimeType() async throws {
        let pasteboardType = NSPasteboard.PasteboardType(mimeType: "image/png")
        #expect(pasteboardType != nil)
        #expect(pasteboardType == .png)
    }

    @Test func testGhosttyReadableContentText() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)

        #expect(pasteboard.ghosttyReadableContent() == .string("hello"))
    }

    @Test func testGhosttyReadableContentFileURL() async throws {
        let pasteboard = makePasteboard()
        let fileURL = URL(fileURLWithPath: "/tmp/ghostty image.png")
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([fileURL as NSURL]))

        #expect(
            pasteboard.ghosttyReadableContent() ==
            .string(Ghostty.Shell.escape(fileURL.path))
        )
    }

    @Test func testGhosttyReadableContentImageOnly() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.declareTypes([.png], owner: nil)
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)

        #expect(pasteboard.ghosttyReadableContent() == .imageOnly)
        #expect(pasteboard.getOpinionatedStringContents() == nil)
    }

    @Test func testGhosttyReadableContentMixedTextAndImage() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .png], owner: nil)
        pasteboard.setString("hello", forType: .string)
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)

        #expect(pasteboard.ghosttyReadableContent() == .string("hello"))
    }

    @Test func testGhosttyReadableContentUnavailable() async throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()

        #expect(pasteboard.ghosttyReadableContent() == .unavailable)
    }
}
