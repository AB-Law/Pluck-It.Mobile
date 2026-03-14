//
//  PluckIt_MobileTests.swift
//  PluckIt.MobileTests
//
//  Created by Akshay B on 13/03/26.
//

import Testing
import Foundation
@testable import PluckIt_Mobile

struct PluckIt_MobileTests {

    @Test func wardrobePagedResponseDecodesObjectSizePayload() throws {
        let json = """
        {
          "items": [
            {
              "id": "upload-1",
              "userId": "local-dev-user",
              "imageUrl": "https://example.test/item-1.webp",
              "brand": "Ami",
              "category": "Tops",
              "price": {
                "amount": 3500,
                "originalCurrency": "INR"
              },
              "dateAdded": "2026-03-04T16:50:16.762562+00:00",
              "wearCount": 0,
              "careInfo": ["dry_clean"],
              "size": {
                "letter": "L",
                "system": "US"
              },
              "condition": "New",
              "colours": [
                { "name": "white", "hex": "#ffffff" }
              ]
            }
          ],
          "nextContinuationToken": "token-123"
        }
        """

        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(WardrobePagedResponse.self, from: data)

        #expect(response.items.count == 1)
        #expect(response.nextContinuationToken == "token-123")

        let item = response.items.first
        #expect(item?.id == "upload-1")
        #expect(item?.brand == "Ami")
        #expect(item?.category == "Tops")
        #expect(item?.wearCount == 0)
        #expect(item?.size?.letter == "L")
        #expect(item?.size?.system == "US")
        #expect(item?.size?.waist == nil)
        #expect(item?.price?.originalCurrency == "INR")
        #expect(item?.colours?.first?.name == "white")
        #expect(item?.colours?.first?.hex == "#ffffff")
        #expect(item?.wearEvents?.isEmpty == true)
    }

    @Test func wardrobePagedResponseDecodesLegacyStringSizePayload() throws {
        let json = """
        {
          "items": [
            {
              "id": "upload-2",
              "brand": "Retro",
              "category": "Bottoms",
              "size": "L",
              "wearCount": 1
            }
          ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(WardrobePagedResponse.self, from: data)

        #expect(response.items.count == 1)
        #expect(response.nextContinuationToken == nil)

        let item = response.items.first
        #expect(item?.id == "upload-2")
        #expect(item?.size?.letter == "L")
        #expect(item?.size?.waist == nil)
        #expect(item?.size?.system == nil)
    }

    @Test func stylistChatEventDecodesTokenAndToolEvents() throws {
        let tokenPayload = """
        {
          "type": "token",
          "content": "hello",
          "traceId": "trace-1",
          "runId": "run-1",
          "model": "gpt",
          "tokenCount": 1,
          "toolLatencyMs": 12
        }
        """
        let tokenData = try #require(tokenPayload.data(using: .utf8))
        let tokenEvent = try JSONDecoder().decode(StylistChatEvent.self, from: tokenData)

        switch tokenEvent {
        case let .token(content, traceId, runId, model, tokenCount, toolLatencyMs):
            #expect(content == "hello")
            #expect(traceId == "trace-1")
            #expect(runId == "run-1")
            #expect(model == "gpt")
            #expect(tokenCount == 1)
            #expect(toolLatencyMs == 12)
        default:
            #expect(Bool(false), "Expected token event")
        }

        let toolPayload = """
        {"type":"tool_use","name":"search_wardrobe","trace_id":"trace-2","run_id":"run-2","tool_latency_ms":25}
        """
        let toolData = try #require(toolPayload.data(using: .utf8))
        let toolEvent = try JSONDecoder().decode(StylistChatEvent.self, from: toolData)

        switch toolEvent {
        case let .toolUse(name, traceId, runId, _, _, _):
            #expect(name == "search_wardrobe")
            #expect(traceId == "trace-2")
            #expect(runId == "run-2")
        default:
            #expect(Bool(false), "Expected tool_use event")
        }
    }

    @Test func stylistSSEParserBuildsEventsFromLines() throws {
        var parser = StylistSSEParser()
        var events: [StylistChatEvent] = []

        events += parser.consume(line: "data: {\"type\":\"token\",\"content\":\"hello\"}")
        #expect(events.isEmpty)

        events += parser.consume(line: "")
        #expect(events.count == 1)
        guard case let .token(content, _, _, _, _, _) = events.first! else {
            #expect(Bool(false), "Expected token event")
            return
        }
        #expect(content == "hello")
        events = []

        events += parser.consume(line: "event: ignored")
        events += parser.consume(line: "data: {\"type\":\"done\"}")
        events += parser.consume(line: "")
        #expect(events.count == 1)
        guard case .done(_, _, _, _, _) = events.first! else {
            #expect(Bool(false), "Expected done event")
            return
        }
    }

    @Test func stylistSSEParserCapturesUnknownEventType() throws {
        var parser = StylistSSEParser()
        var events: [StylistChatEvent] = []

        events += parser.consume(line: "data: {\"type\":\"weird_type\",\"content\":\"something\"}")
        events += parser.consume(line: "")

        #expect(events.count == 1)
        guard case let .unknown(type, _, _, _, _, _) = events.first! else {
            #expect(Bool(false), "Expected unknown event")
            return
        }
        #expect(type == "weird_type")
    }

    @Test func stylistSSEParserHandlesHeartbeatPing() throws {
        var parser = StylistSSEParser()
        var events: [StylistChatEvent] = []

        events += parser.consume(line: ": keep-alive")
        events += parser.consume(line: "")

        #expect(events.count == 0)
    }

    @Test func stylistChatEventFallbacksTraceIdFromRequest() throws {
        let event = StylistChatEvent.done(
            traceId: nil,
            runId: nil,
            model: nil,
            tokenCount: nil,
            toolLatencyMs: nil
        )
            .withDefaultTraceId("trace-fallback")
        switch event {
        case let .done(traceId, _, _, _, _):
            #expect(traceId == "trace-fallback")
        default:
            #expect(Bool(false), "Expected done event")
        }
    }

    @Test func stylistChatRequestUsesExpectedJSONKeys() throws {
        let request = StylistChatRequest(
            message: "Find me a blue jacket",
            recentMessages: [
                StylistMessage(role: .user, content: "Need something casual")
            ],
            selectedItemIds: ["item-1", "item-2"],
            traceId: "trace-abc"
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data: Data
        do {
            data = try encoder.encode(request)
        } catch {
            Issue.record("Failed to encode StylistChatRequest: \(error)")
            return
        }
        let raw = try #require(JSONSerialization.jsonObject(with: data, options: [] ) as? [String: Any])

        #expect(raw["message"] as? String == "Find me a blue jacket")
        #expect(raw["trace_id"] as? String == "trace-abc")
        #expect(raw["selected_item_ids"] as? [String] == ["item-1", "item-2"])
        #expect(raw["recent_messages"] is [[String: Any]])
    }

    @Test func apiClientEndpointURLDeduplicatesApiSegment() throws {
        let apiRootClient = APIClient(baseUrl: try #require(URL(string: "https://example.test/api")))
        #expect(apiRootClient.endpointURL(path: "api/collections").path == "/api/collections")

        let nestedApiClient = APIClient(baseUrl: try #require(URL(string: "https://example.test/v1/api")))
        #expect(nestedApiClient.endpointURL(path: "api/collections").path == "/v1/api/collections")
    }

    @Test func apiClientEndpointURLEmptyNormalizedPathReturnsRootPath() throws {
        let client = APIClient(baseUrl: try #require(URL(string: "https://example.test")))
        #expect(client.endpointURL(path: "").path == "/")
    }

    @Test func apiClientEndpointURLCollapsesExtraSlashes() throws {
        let client = APIClient(baseUrl: try #require(URL(string: "https://example.test/api")))
        #expect(client.endpointURL(path: "api//v1").path == "/api/v1")
        #expect(client.endpointURL(path: "/api//v1").path == "/api/v1")
    }

    @Test func apiClientEndpointURLPreservesPercentEncodedSegments() throws {
        let client = APIClient(baseUrl: try #require(URL(string: "https://example.test/api")))
        let encodedPathURL = client.endpointURL(path: "items/photos%2Fautumn%2Fset")
        #expect(encodedPathURL.absoluteString == "https://example.test/api/items/photos%2Fautumn%2Fset")
        #expect(!encodedPathURL.absoluteString.contains("photos/autumn/set"))
    }

    @Test func apiClientEndpointURLJoinsBaseAndPathWithoutExtraSlashes() throws {
        let client = APIClient(baseUrl: try #require(URL(string: "https://example.test/base")))
        #expect(client.endpointURL(path: "resources/2026").path == "/base/resources/2026")
        #expect(client.endpointURL(path: "/resources//2026").path == "/base/resources/2026")
    }

}
