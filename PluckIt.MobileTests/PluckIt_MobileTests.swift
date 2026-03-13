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

}
