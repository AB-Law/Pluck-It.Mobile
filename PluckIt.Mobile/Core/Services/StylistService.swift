import Foundation

/// Streaming chat service that calls `/api/chat` on the processor backend.
final class StylistService {
    private let client: APIClient
    private let session: URLSession
    private let debugLoggingEnabled: Bool

    /// Creates a stylist chat service bound to a given API client.
    init(client: APIClient, session: URLSession = .shared, debugLoggingEnabled: Bool = false) {
        self.client = client
        self.session = session
        self.debugLoggingEnabled = debugLoggingEnabled
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
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    guard let body = try? encoder.encode(request) else {
                        throw StylistServiceError.requestEncodingFailed
                    }
                    let streamingRequest = await client.makeStreamingRequest(
                        method: "POST",
                        path: "api/chat",
                        body: body,
                        headers: [
                            "Content-Type": "application/json",
                            "Accept": "text/event-stream"
                        ]
                    )
                    if debugLoggingEnabled {
                        let loggedHeaders = Dictionary(
                            uniqueKeysWithValues: (streamingRequest.allHTTPHeaderFields ?? [:]).map { key, value in
                                if key.caseInsensitiveCompare("Authorization") == .orderedSame {
                                    return (key, "[redacted]")
                                }
                                return (key, value)
                            }
                        )
                        print("🛰 StylistService request: POST \(streamingRequest.url?.absoluteString ?? "<unknown>")")
                        print("🛰 headers: \(loggedHeaders)")
                        print("🛰 body bytes: \(body.count)")
                    }

                    let (bytes, response) = try await session.bytes(for: streamingRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw StylistServiceError.invalidHTTPResponse
                    }
                    if debugLoggingEnabled {
                        print("🛰 StylistService response: \(httpResponse.statusCode) \(streamingRequest.url?.absoluteString ?? "<unknown>")")
                    }
                    guard (200 ... 299).contains(httpResponse.statusCode) else {
                        var errorBody = Data()
                        for try await byte in bytes {
                            errorBody.append(byte)
                        }
                        let message = errorBody.isEmpty ? nil : String(data: errorBody, encoding: .utf8)
                        throw StylistServiceError.httpFailure(statusCode: httpResponse.statusCode, body: message, requestURL: streamingRequest.url)
                    }

                    var parser = StylistSSEParser()
                    for try await line in bytes.lines {
                        if debugLoggingEnabled {
                            print("🛰 StylistService stream line: \(line)")
                        }
                        let events = parser.consume(line: line).map({ $0.withDefaultTraceId(traceId) })
                        if events.isEmpty {
                            if debugLoggingEnabled {
                                print("🛰 StylistService parsed 0 events for line")
                            }
                        }
                        for event in events {
                            if debugLoggingEnabled {
                                print("🛰 StylistService emit: \(event)")
                            }
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
