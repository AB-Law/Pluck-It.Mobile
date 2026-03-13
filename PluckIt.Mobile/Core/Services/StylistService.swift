import Foundation

/// Streaming chat service that calls `/api/chat` on the processor backend.
final class StylistService {
    private let client: APIClient
    private let session: URLSession

    /// Creates a stylist chat service bound to a given API client.
    init(client: APIClient, session: URLSession = .shared) {
        self.client = client
        self.session = session
    }

    /// Starts streaming a stylist conversation and yields typed events as they arrive.
    func streamChat(
        message: String,
        recentMessages: [StylistMessage],
        selectedItemIds: [String]?,
    ) -> AsyncThrowingStream<StylistChatEvent, Error> {
        let traceId = UUID().uuidString
        let request = StylistChatRequest(
            message: message,
            recentMessages: recentMessages,
            selectedItemIds: selectedItemIds,
            traceId: traceId
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let body = try? client.jsonEncoder.encode(request) else {
                        throw StylistServiceError.requestEncodingFailed
                    }
                    let bodyText = String(data: body, encoding: .utf8) ?? "<invalid utf8>"

                    let request = await client.makeStreamingRequest(
                        method: "POST",
                        path: "api/chat",
                        body: body,
                        headers: [
                            "Content-Type": "application/json",
                            "Accept": "text/event-stream"
                        ]
                    )
                    print("🛰 StylistService request: POST \(request.url?.absoluteString ?? "<unknown>")")
                    print("🛰 headers: \(request.allHTTPHeaderFields ?? [:])")
                    print("🛰 body: \(bodyText)")

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw StylistServiceError.invalidHTTPResponse
                    }
                    print("🛰 StylistService response: \(httpResponse.statusCode) \(request.url?.absoluteString ?? "<unknown>")")
                    guard (200 ... 299).contains(httpResponse.statusCode) else {
                        var errorBody = Data()
                        for try await byte in bytes {
                            errorBody.append(byte)
                        }
                        let message = errorBody.isEmpty ? nil : String(data: errorBody, encoding: .utf8)
                        throw StylistServiceError.httpFailure(statusCode: httpResponse.statusCode, body: message, requestURL: request.url)
                    }

                    var parser = StylistSSEParser()
                    for try await line in bytes.lines {
                        print("🛰 StylistService stream line: \(line)")
                        let events = parser.consume(line: line).map({ $0.withDefaultTraceId(traceId) })
                        if events.isEmpty {
                            print("🛰 StylistService parsed 0 events for line")
                        }
                        for event in events {
                            print("🛰 StylistService emit: \(event)")
                            continuation.yield(event)
                            if case .done = event {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    for event in parser.finish().map({ $0.withDefaultTraceId(traceId) }) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Chat request failure categories for stylist streaming flow.
enum StylistServiceError: LocalizedError {
    case invalidHTTPResponse
    case requestEncodingFailed
    case httpFailure(statusCode: Int, body: String?, requestURL: URL?)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "Chat stream returned a non-HTTP response."
        case .requestEncodingFailed:
            return "Failed to encode stylist request payload."
        case let .httpFailure(statusCode, body, requestURL):
            let message = body.flatMap { " — \($0)" } ?? ""
            if let requestURL {
                return "Chat request failed with HTTP \(statusCode) for \(requestURL.absoluteString)\(message)"
            }
            return "Chat request failed with HTTP \(statusCode)\(message)"
        }
    }
}
