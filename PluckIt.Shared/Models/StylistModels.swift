import Foundation

/// One message in the stylist chat history sent as context for /api/chat.
enum StylistMessageRole: String, Codable, Equatable {
    case user
    case assistant
}

/// One message payload used in the stylist chat request history.
struct StylistMessage: Codable, Equatable {
    let role: StylistMessageRole
    let content: String
}

/// Chat request body for streaming conversation endpoint.
struct StylistChatRequest: Codable, Equatable {
    let message: String
    let recentMessages: [StylistMessage]
    let selectedItemIds: [String]?
    let traceId: String

    enum CodingKeys: String, CodingKey {
        case message
        case recent_messages
        case selected_item_ids
        case trace_id
    }

    init(message: String, recentMessages: [StylistMessage], selectedItemIds: [String]?, traceId: String) {
        self.message = message
        self.recentMessages = recentMessages
        self.selectedItemIds = selectedItemIds
        self.traceId = traceId
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        recentMessages = try container.decode([StylistMessage].self, forKey: .recent_messages)
        selectedItemIds = try container.decodeIfPresent([String].self, forKey: .selected_item_ids)
        traceId = try container.decode(String.self, forKey: .trace_id)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(recentMessages, forKey: .recent_messages)
        try container.encode(traceId, forKey: .trace_id)
        if let selectedItemIds {
            try container.encode(selectedItemIds, forKey: .selected_item_ids)
        } else {
            try container.encodeNil(forKey: .selected_item_ids)
        }
    }
}

/// Typed event emitted by the stylist AI stream.
enum StylistChatEvent: Codable, Equatable {
    case token(
        content: String,
        traceId: String?,
        runId: String?,
        model: String?,
        tokenCount: Int?,
        toolLatencyMs: Int?
    )
    case toolUse(
        name: String,
        traceId: String?,
        runId: String?,
        model: String?,
        tokenCount: Int?,
        toolLatencyMs: Int?
    )
    case toolResult(
        name: String,
        summary: String?,
        traceId: String?,
        runId: String?,
        model: String?,
        tokenCount: Int?,
        toolLatencyMs: Int?
    )
    case memoryUpdate(
        updated: Bool,
        traceId: String?,
        runId: String?,
        model: String?,
        tokenCount: Int?,
        toolLatencyMs: Int?
    )
    case error(
        content: String,
        traceId: String?,
        runId: String?,
        model: String?,
        tokenCount: Int?,
        toolLatencyMs: Int?
    )
    case done(
        traceId: String?,
        runId: String?,
        model: String?,
        tokenCount: Int?,
        toolLatencyMs: Int?
    )
    case unknown(
        type: String,
        traceId: String?,
        runId: String?,
        model: String?,
        tokenCount: Int?,
        toolLatencyMs: Int?
    )

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case name
        case summary
        case updated
        case traceId
        case runId
        case model
        case tokenCount
        case toolLatencyMs
        case trace_id
        case run_id
        case token_count
        case tool_latency_ms
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let traceId = try container.decodeIfPresent(String.self, forKey: .traceId)
            ?? container.decodeIfPresent(String.self, forKey: .trace_id)
        let runId = try container.decodeIfPresent(String.self, forKey: .runId)
            ?? container.decodeIfPresent(String.self, forKey: .run_id)
        let model = try container.decodeIfPresent(String.self, forKey: .model)
        let tokenCount = StylistChatEvent.decodeInt(container, forKey: .tokenCount)
            ?? StylistChatEvent.decodeInt(container, forKey: .token_count)
        let toolLatencyMs = StylistChatEvent.decodeInt(container, forKey: .toolLatencyMs)
            ?? StylistChatEvent.decodeInt(container, forKey: .tool_latency_ms)

        switch type {
        case "token":
            let content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
            self = .token(
                content: content,
                traceId: traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        case "tool_use":
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? "tool"
            self = .toolUse(
                name: name,
                traceId: traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        case "tool_result":
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? "tool"
            let summary = try container.decodeIfPresent(String.self, forKey: .summary)
            self = .toolResult(
                name: name,
                summary: summary,
                traceId: traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        case "memory_update":
            let updated = try container.decodeIfPresent(Bool.self, forKey: .updated) ?? false
            self = .memoryUpdate(
                updated: updated,
                traceId: traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        case "error":
            let content = try container.decodeIfPresent(String.self, forKey: .content) ?? "Stylist returned an error."
            self = .error(
                content: content,
                traceId: traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        case "done":
            self = .done(
                traceId: traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        default:
            self = .unknown(
                type: type,
                traceId: traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .token(content, traceId, runId, model, tokenCount, toolLatencyMs):
            try container.encode("token", forKey: .type)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(traceId, forKey: .traceId)
            try container.encodeIfPresent(runId, forKey: .runId)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(tokenCount, forKey: .tokenCount)
            try container.encodeIfPresent(toolLatencyMs, forKey: .toolLatencyMs)
        case let .toolUse(name, traceId, runId, model, tokenCount, toolLatencyMs):
            try container.encode("tool_use", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(traceId, forKey: .traceId)
            try container.encodeIfPresent(runId, forKey: .runId)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(tokenCount, forKey: .tokenCount)
            try container.encodeIfPresent(toolLatencyMs, forKey: .toolLatencyMs)
        case let .toolResult(name, summary, traceId, runId, model, tokenCount, toolLatencyMs):
            try container.encode("tool_result", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(summary, forKey: .summary)
            try container.encodeIfPresent(traceId, forKey: .traceId)
            try container.encodeIfPresent(runId, forKey: .runId)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(tokenCount, forKey: .tokenCount)
            try container.encodeIfPresent(toolLatencyMs, forKey: .toolLatencyMs)
        case let .memoryUpdate(updated, traceId, runId, model, tokenCount, toolLatencyMs):
            try container.encode("memory_update", forKey: .type)
            try container.encode(updated, forKey: .updated)
            try container.encodeIfPresent(traceId, forKey: .traceId)
            try container.encodeIfPresent(runId, forKey: .runId)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(tokenCount, forKey: .tokenCount)
            try container.encodeIfPresent(toolLatencyMs, forKey: .toolLatencyMs)
        case let .error(content, traceId, runId, model, tokenCount, toolLatencyMs):
            try container.encode("error", forKey: .type)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(traceId, forKey: .traceId)
            try container.encodeIfPresent(runId, forKey: .runId)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(tokenCount, forKey: .tokenCount)
            try container.encodeIfPresent(toolLatencyMs, forKey: .toolLatencyMs)
        case let .done(traceId, runId, model, tokenCount, toolLatencyMs):
            try container.encode("done", forKey: .type)
            try container.encodeIfPresent(traceId, forKey: .traceId)
            try container.encodeIfPresent(runId, forKey: .runId)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(tokenCount, forKey: .tokenCount)
            try container.encodeIfPresent(toolLatencyMs, forKey: .toolLatencyMs)
        case let .unknown(type, traceId, runId, model, tokenCount, toolLatencyMs):
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(traceId, forKey: .traceId)
            try container.encodeIfPresent(runId, forKey: .runId)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(tokenCount, forKey: .tokenCount)
            try container.encodeIfPresent(toolLatencyMs, forKey: .toolLatencyMs)
        }
    }

    /// Returns a copy of the event with fallback trace fields when absent.
    func withDefaultTraceId(_ traceId: String) -> StylistChatEvent {
        switch self {
        case let .token(content, currentTraceId, runId, model, tokenCount, toolLatencyMs):
            return .token(
                content: content,
                traceId: currentTraceId ?? traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        case let .toolUse(name, currentTraceId, runId, model, tokenCount, toolLatencyMs):
            return .toolUse(
                name: name,
                traceId: currentTraceId ?? traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        case let .toolResult(name, summary, currentTraceId, runId, model, tokenCount, toolLatencyMs):
            return .toolResult(
                name: name,
                summary: summary,
                traceId: currentTraceId ?? traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        case let .memoryUpdate(updated, currentTraceId, runId, model, tokenCount, toolLatencyMs):
            return .memoryUpdate(
                updated: updated,
                traceId: currentTraceId ?? traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        case let .error(content, currentTraceId, runId, model, tokenCount, toolLatencyMs):
            return .error(
                content: content,
                traceId: currentTraceId ?? traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        case let .done(currentTraceId, runId, model, tokenCount, toolLatencyMs):
            return .done(
                traceId: currentTraceId ?? traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        case let .unknown(type, currentTraceId, runId, model, tokenCount, toolLatencyMs):
            return .unknown(
                type: type,
                traceId: currentTraceId ?? traceId,
                runId: runId,
                model: model,
                tokenCount: tokenCount,
                toolLatencyMs: toolLatencyMs
            )
        }
    }

    private static nonisolated func decodeInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }
        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(doubleValue)
        }
        return nil
    }
}

/// Assembles SSE `data:` lines into event objects for /api/chat streaming responses.
struct StylistSSEParser {
    private var dataChunks: [String] = []
    private let decoder = JSONDecoder()

    mutating func consume(line: String) -> [StylistChatEvent] {
        let cleaned = line.trimmingCharacters(in: .newlines)
        let text = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return finish()
        }

        guard text.lowercased().hasPrefix("data:") else {
            return []
        }

        let payload = String(text.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else {
            return []
        }

        dataChunks.append(payload)
        return []
    }

    mutating func finish() -> [StylistChatEvent] {
        guard !dataChunks.isEmpty else {
            return []
        }

        let frame = dataChunks.joined(separator: "\n")
        dataChunks.removeAll(keepingCapacity: true)
        return decodeEvents(from: frame)
    }

    private func decodeEvents(from payloadString: String) -> [StylistChatEvent] {
        guard let payload = payloadString.data(using: .utf8) else {
            return []
        }
        if let event = try? decoder.decode(StylistChatEvent.self, from: payload) {
            return [event]
        }
        if let events = try? decoder.decode([StylistChatEvent].self, from: payload) {
            return events
        }

        var events: [StylistChatEvent] = []
        let lines = payloadString
            .split(whereSeparator: \.isNewline)
            .map { String($0) }

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let raw = trimmedLine.lowercased().hasPrefix("data:")
                ? trimmedLine.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                : trimmedLine
            if raw.isEmpty { continue }
            if let event = try? decoder.decode(StylistChatEvent.self, from: Data(raw.utf8)) {
                events.append(event)
            } else if let array = try? decoder.decode([StylistChatEvent].self, from: Data(raw.utf8)) {
                events.append(contentsOf: array)
            }
        }

        return events
    }
}
