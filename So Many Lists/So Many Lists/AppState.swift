import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var pendingImport: SharedListPayload?
    @Published var importErrorMessage: String?

    let shareCodec = ListShareCodec()

    func handle(url: URL) {
        do {
            pendingImport = try shareCodec.decode(url: url)
            importErrorMessage = nil
        } catch {
            importErrorMessage = "This shared list could not be imported."
        }
    }
}
