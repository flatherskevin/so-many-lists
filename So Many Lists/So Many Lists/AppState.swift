import Combine
import Foundation

struct AnnouncementTile: Identifiable, Hashable {
    let id: String
    let title: String
    let message: String
    let badges: [String]
    let symbolName: String
    let accentName: String
    let detailTitle: String
    let detailBody: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var pendingImport: SharedListPayload?
    @Published var importErrorMessage: String?
    @Published private(set) var dismissedAnnouncementIDs: Set<String>

    let shareCodec = ListShareCodec()
    private let dismissedAnnouncementsKey = "dismissedAnnouncementIDs"

    init() {
        dismissedAnnouncementIDs = Set(
            (UserDefaults.standard.array(forKey: dismissedAnnouncementsKey) as? [String]) ?? []
        )
    }

    func handle(url: URL) {
        do {
            pendingImport = try shareCodec.decode(url: url)
            importErrorMessage = nil
        } catch {
            importErrorMessage = "This shared list could not be imported."
        }
    }

    var activeAnnouncements: [AnnouncementTile] {
        AnnouncementCatalog.tiles.filter { !dismissedAnnouncementIDs.contains($0.id) }
    }

    func dismissAnnouncement(id: String) {
        dismissedAnnouncementIDs.insert(id)
        persistDismissedAnnouncements()
    }

    func restoreAnnouncement(id: String) {
        dismissedAnnouncementIDs.remove(id)
        persistDismissedAnnouncements()
    }

    private func persistDismissedAnnouncements() {
        UserDefaults.standard.set(Array(dismissedAnnouncementIDs).sorted(), forKey: dismissedAnnouncementsKey)
    }
}

enum AnnouncementCatalog {
    static let tiles: [AnnouncementTile] = [
        AnnouncementTile(
            id: "welcome-multimodal-ai",
            title: "Build lists from the messiest inputs.",
            message: "Turn prompts, voice notes, photos, and videos into clean local lists you can actually use.",
            badges: ["On-device storage", "Multimodal input"],
            symbolName: "sparkles.rectangle.stack.fill",
            accentName: "teal",
            detailTitle: "Use AI Where It Helps",
            detailBody: "Create a list from text, voice, photos, or videos, then keep refining it inside the list editor with Apple Intelligence."
        ),
        AnnouncementTile(
            id: "starter-sets",
            title: "Save your own starter sets.",
            message: "Build reusable packing, grocery, or trip templates once, then apply them without retyping.",
            badges: ["Reusable templates", "Duplicate-safe merge"],
            symbolName: "square.stack.3d.up.fill",
            accentName: "orange",
            detailTitle: "Starter Sets",
            detailBody: "Open Starter Sets from the toolbar to create your own reusable item bundles. Apply them while creating a new list or from an existing list."
        )
    ]
}
