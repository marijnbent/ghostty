import AppKit
import Testing
@testable import Ghostty

struct SurfaceViewAppKitTests {
    @Test func testImagePasteKeyEquivalentPassthroughForImageOnlyClipboard() async throws {
        #expect(
            Ghostty.SurfaceView.shouldPassthroughImagePasteKeyEquivalent(
                eventKeyEquivalent: "v",
                eventModifiers: [.command],
                pasteKeyEquivalent: "v",
                pasteModifiers: [.command],
                clipboardContent: .imageOnly
            )
        )
    }

    @Test func testImagePasteKeyEquivalentDoesNotPassthroughTextClipboard() async throws {
        #expect(
            !Ghostty.SurfaceView.shouldPassthroughImagePasteKeyEquivalent(
                eventKeyEquivalent: "v",
                eventModifiers: [.command],
                pasteKeyEquivalent: "v",
                pasteModifiers: [.command],
                clipboardContent: .string("hello")
            )
        )
    }

    @Test func testImagePasteKeyEquivalentRequiresShortcutMatch() async throws {
        #expect(
            !Ghostty.SurfaceView.shouldPassthroughImagePasteKeyEquivalent(
                eventKeyEquivalent: "v",
                eventModifiers: [.command],
                pasteKeyEquivalent: "v",
                pasteModifiers: [.command, .shift],
                clipboardContent: .imageOnly
            )
        )
    }
}
