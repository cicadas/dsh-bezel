import Foundation

/// One find-in-page directive for a tab's WebView.
///
/// Commands ride the same token pattern as the reload request: the view hands
/// the latest command to the representable, and the coordinator applies it
/// only when the token has moved, so SwiftUI re-renders can never re-issue an
/// action the user did not ask for again.
struct PageFindCommand: Equatable {
    enum Action: Equatable {
        /// Open the find bar (⌘F); AppKit re-focuses its field when already open.
        case show
        /// Jump to the next match (⌘G).
        case next
        /// Jump to the previous match (⇧⌘G).
        case previous
        /// Take the page's selected text as the search string (⌘E).
        case useSelection
    }

    /// Monotonic per tab; a token is consumed exactly once.
    let token: Int
    let action: Action
}
