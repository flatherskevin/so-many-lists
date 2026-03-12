import Foundation

struct ListShareCodec {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let baseURL = URL(string: "somanylists://import")!

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func payload(for document: ListDocument) -> SharedListPayload {
        SharedListPayload(
            draft: document.makeDraft(sourceKind: .imported),
            exportedAt: .now
        )
    }

    func url(for payload: SharedListPayload) throws -> URL {
        let data = try encoder.encode(payload)
        let token = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "payload", value: token)]
        return components?.url ?? baseURL
    }

    func decode(url: URL) throws -> SharedListPayload {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "payload" })?.value else {
            throw CocoaError(.coderReadCorrupt)
        }

        let padded = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .padding(toLength: ((token.count + 3) / 4) * 4, withPad: "=", startingAt: 0)

        guard let data = Data(base64Encoded: padded) else {
            throw CocoaError(.coderReadCorrupt)
        }

        return try decoder.decode(SharedListPayload.self, from: data)
    }

    func shareMessage(for document: ListDocument) -> String {
        let payload = payload(for: document)
        let link = (try? url(for: payload).absoluteString) ?? "somanylists://import"
        let text = document.renderShareText()
        return "\(document.title)\n\n\(text)\n\nOpen in So Many Lists:\n\(link)"
    }
}

extension ListDocument {
    func renderShareText() -> String {
        let sectionText = sortedSections.map { section in
            let entries = section.sortedEntries.map { entry in
                let prefix = entry.isComplete ? "[x]" : "[ ]"
                var details: [String] = []
                if !entry.quantity.isEmpty { details.append(entry.quantity) }
                if !entry.place.isEmpty { details.append(entry.place) }
                if !entry.entryNotes.isEmpty { details.append(entry.entryNotes) }
                let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
                return "\(prefix) \(entry.title)\(suffix)"
            }.joined(separator: "\n")
            return "\(section.title)\n\(entries)"
        }.joined(separator: "\n\n")

        return sectionText
    }
}
