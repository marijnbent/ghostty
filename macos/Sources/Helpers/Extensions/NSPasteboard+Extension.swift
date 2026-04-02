import AppKit
import GhosttyKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    /// Initialize a pasteboard type from a MIME type string
    init?(mimeType: String) {
        // Explicit mappings for common MIME types
        switch mimeType {
        case "text/plain":
            self = .string
            return
        default:
            break
        }

        // Try to get UTType from MIME type
        guard let utType = UTType(mimeType: mimeType) else {
            // Fallback: use the MIME type directly as identifier
            self.init(mimeType)
            return
        }

        // Use the UTType's identifier
        self.init(utType.identifier)
    }
}

extension NSPasteboard {
    enum GhosttyReadableContent: Equatable {
        case string(String)
        case imageOnly
        case unavailable
    }

    /// The pasteboard to used for Ghostty selection.
    static var ghosttySelection: NSPasteboard = {
        NSPasteboard(name: .init("com.mitchellh.ghostty.selection"))
    }()

    /// Returns the contents of the pasteboard following Ghostty's paste semantics.
    ///
    /// This distinguishes image-only clipboard contents from truly unavailable
    /// clipboard contents so key handling can choose whether to fall through to
    /// the terminal application.
    func ghosttyReadableContent() -> GhosttyReadableContent {
        if let urls = readObjects(forClasses: [NSURL.self]) as? [URL],
           urls.count > 0 {
            return .string(
                urls
                    .map { $0.isFileURL ? Ghostty.Shell.escape($0.path) : $0.absoluteString }
                    .joined(separator: " ")
            )
        }

        if let string = self.string(forType: .string) {
            return .string(string)
        }

        if hasImageContents {
            return .imageOnly
        }

        return .unavailable
    }

    /// Gets the contents of the pasteboard as a string following a specific set of semantics.
    /// Does these things in order:
    /// - Tries to get the absolute filesystem path of the file in the pasteboard if there is one and ensures the file path is properly escaped.
    /// - Tries to get any string from the pasteboard.
    /// If all of the above fail, returns None.
    func getOpinionatedStringContents() -> String? {
        guard case let .string(string) = ghosttyReadableContent() else { return nil }
        return string
    }

    /// The pasteboard for the Ghostty enum type.
    static func ghostty(_ clipboard: ghostty_clipboard_e) -> NSPasteboard? {
        switch clipboard {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return Self.general

        case GHOSTTY_CLIPBOARD_SELECTION:
            return Self.ghosttySelection

        default:
            return nil
        }
    }

    var hasImageContents: Bool {
        guard let types = self.types else { return false }
        return types.contains { type in
            guard let utType = UTType(type.rawValue) else { return false }
            return utType.conforms(to: .image)
        }
    }
}
