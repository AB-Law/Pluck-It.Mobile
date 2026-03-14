import Foundation

/// Generic JSON network client used by all services in the app.
final class APIClient {
    struct ErrorResponse: Error, LocalizedError {
        let statusCode: Int
        let body: String?
        let requestURL: URL?

        var errorDescription: String? {
            let message = body.flatMap { " — \($0)" } ?? ""
            if let requestURL {
                return "Request failed with HTTP \(statusCode) for \(requestURL.absoluteString)\(message)"
            }
            return "Request failed with HTTP \(statusCode)\(message)"
        }
    }

    typealias TokenProvider = () async -> String?

    private let baseUrl: URL
    private let session: URLSession
    private let tokenProvider: TokenProvider?
    private let debugLoggingEnabled: Bool

    init(baseUrl: URL, session: URLSession = .shared, tokenProvider: TokenProvider? = nil, debugLoggingEnabled: Bool = false) {
        self.baseUrl = baseUrl
        self.session = session
        self.tokenProvider = tokenProvider
        self.debugLoggingEnabled = debugLoggingEnabled
    }

    lazy var jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    lazy var jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Sends a request and decodes the response payload.
    func send<T: Decodable>(
        method: String = "GET",
        path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval = 30,
    ) async throws -> T {
        let url = buildUrl(path: path, query: query)
        func buildRequest(for token: String?) -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = timeout
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return request
        }

        let requestToken = await tokenProvider?()
        var urlRequest = buildRequest(for: requestToken)
        logTokenAudit(method: method, url: url, token: requestToken)
        logRequest(method: method, url: url, headers: urlRequest.allHTTPHeaderFields ?? [:], body: body)

        do {
            var (data, response) = try await session.data(for: urlRequest)
            guard var httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if httpResponse.statusCode == 401, let tokenProvider {
                let refreshedToken = await tokenProvider()
                if let refreshedToken, !refreshedToken.isEmpty {
                    urlRequest = buildRequest(for: refreshedToken)
                    logTokenAudit(method: method, url: url, token: refreshedToken)
                    logRequest(method: method, url: url, headers: urlRequest.allHTTPHeaderFields ?? [:], body: body)
                    let retryPair = try await session.data(for: urlRequest)
                    data = retryPair.0
                    guard let retryResponse = retryPair.1 as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    httpResponse = retryResponse
                }
            }

            let bodyText = String(data: data, encoding: .utf8)
            logResponse(url: url, statusCode: httpResponse.statusCode, body: bodyText)

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    logUnauthorizedResponse(method: method, url: url, body: bodyText)
                }
                throw ErrorResponse(statusCode: httpResponse.statusCode, body: bodyText, requestURL: url)
            }

            do {
                return try jsonDecoder.decode(T.self, from: data)
            } catch {
                logDecodeFailure(type: String(describing: T.self), url: url, body: bodyText, error: error)
                throw error
            }
        } catch {
            guard !isCancellationError(error) else {
                throw error
            }
            logError(context: "Request failed for \(method) \(url.absoluteString)", error: error)
            throw error
        }
    }

    /// Sends an action-only request and ignores response payload.
    func send(
        method: String = "POST",
        path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval = 30
    ) async throws {
        _ = try await sendVoid(method: method, path: path, query: query, body: body, headers: headers, timeout: timeout)
    }

    func sendVoid(
        method: String = "POST",
        path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval = 30
    ) async throws -> Void {
        let url = buildUrl(path: path, query: query)
        func buildRequest(for token: String?) -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = timeout
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return request
        }

        let requestToken = await tokenProvider?()
        var urlRequest = buildRequest(for: requestToken)
        logTokenAudit(method: method, url: url, token: requestToken)
        logRequest(method: method, url: url, headers: urlRequest.allHTTPHeaderFields ?? [:], body: body)

        do {
            var (data, response) = try await session.data(for: urlRequest)
            guard var httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 401, let tokenProvider {
                let refreshedToken = await tokenProvider()
                if let refreshedToken, !refreshedToken.isEmpty {
                    urlRequest = buildRequest(for: refreshedToken)
                    logTokenAudit(method: method, url: url, token: refreshedToken)
                    logRequest(method: method, url: url, headers: urlRequest.allHTTPHeaderFields ?? [:], body: body)
                    let retryPair = try await session.data(for: urlRequest)
                    data = retryPair.0
                    guard let retryResponse = retryPair.1 as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    httpResponse = retryResponse
                }
            }

            let bodyText = String(data: data, encoding: .utf8)
            logResponse(url: url, statusCode: httpResponse.statusCode, body: bodyText)

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    logUnauthorizedResponse(method: method, url: url, body: bodyText)
                }
                throw ErrorResponse(statusCode: httpResponse.statusCode, body: bodyText, requestURL: url)
            }
        } catch {
            guard !isCancellationError(error) else {
                throw error
            }
            logError(context: "Action request failed for \(method) \(url.absoluteString)", error: error)
            throw error
        }
    }

    /// Uploads image data as multipart/form-data and decodes the response.
    func uploadMultipart<T: Decodable>(
        path: String,
        imageData: Data,
        fileName: String = "image.jpg",
        mimeType: String = "image/jpeg",
        timeout: TimeInterval = 60,
        extraFields: [String: String] = [:]
    ) async throws -> T {
        let url = buildUrl(path: path, query: [:])
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        // Append extra text fields before the file part
        for (name, value) in extraFields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        func buildRequest(for token: String?) -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.httpBody = body
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return request
        }

        let requestToken = await tokenProvider?()
        var urlRequest = buildRequest(for: requestToken)
        logTokenAudit(method: "POST", url: url, token: requestToken)
        logRequest(method: "POST", url: url, headers: urlRequest.allHTTPHeaderFields ?? [:], body: nil)

        do {
            var (data, response) = try await session.data(for: urlRequest)
            guard var httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 401, let tokenProvider {
                let refreshedToken = await tokenProvider()
                if let refreshedToken, !refreshedToken.isEmpty {
                    urlRequest = buildRequest(for: refreshedToken)
                    logTokenAudit(method: "POST", url: url, token: refreshedToken)
                    logRequest(method: "POST", url: url, headers: urlRequest.allHTTPHeaderFields ?? [:], body: nil)
                    let retryPair = try await session.data(for: urlRequest)
                    data = retryPair.0
                    guard let retryResponse = retryPair.1 as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    httpResponse = retryResponse
                }
            }

            let bodyText = String(data: data, encoding: .utf8)
            logResponse(url: url, statusCode: httpResponse.statusCode, body: bodyText)
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    logUnauthorizedResponse(method: "POST", url: url, body: bodyText)
                }
                throw ErrorResponse(statusCode: httpResponse.statusCode, body: bodyText, requestURL: url)
            }
            do {
                return try jsonDecoder.decode(T.self, from: data)
            } catch {
                logDecodeFailure(type: String(describing: T.self), url: url, body: bodyText, error: error)
                throw error
            }
        } catch {
            guard !isCancellationError(error) else { throw error }
            logError(context: "Upload failed for POST \(url.absoluteString)", error: error)
            throw error
        }
    }

    func makeStreamingRequest(
        method: String = "POST",
        path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async -> URLRequest {
        let requestURL = endpointURL(path: path, query: query)
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let requestToken = await tokenProvider?()
        if let token = requestToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        logTokenAudit(method: method, url: requestURL, token: requestToken)
        return request
    }

    func endpointURL(path: String, query: [String: String] = [:]) -> URL {
        let requestedSegments = (path.hasPrefix("/") ? String(path.dropFirst()) : path)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        let basePath = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? baseUrl.path
        let baseSegments = basePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        var normalizedRequested = requestedSegments
        if normalizedRequested.first == "api", baseSegments.last == "api" {
            normalizedRequested.removeFirst()
        }

        let normalizedSegments = baseSegments + normalizedRequested
        let normalizedPath = normalizedSegments.isEmpty ? "/" : "/\(normalizedSegments.joined(separator: "/"))"

        guard var components = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false) else {
            let relativePath = normalizedPath == "/" ? "" : String(normalizedPath.dropFirst())
            var fallbackURL = baseUrl
            if !relativePath.isEmpty {
                fallbackURL = baseUrl.appendingPathComponent(relativePath, isDirectory: false)
            }
            if !query.isEmpty,
               var fallbackComponents = URLComponents(url: fallbackURL, resolvingAgainstBaseURL: false) {
                fallbackComponents.queryItems = query
                    .map { URLQueryItem(name: $0.key, value: $0.value) }
                    .sorted { $0.name < $1.name }
                return fallbackComponents.url ?? fallbackURL
            }
            return fallbackURL
        }

        components.percentEncodedPath = normalizedPath
        if !query.isEmpty {
            components.queryItems = query
                .map { URLQueryItem(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name }
        } else {
            components.queryItems = nil
        }
        return components.url ?? baseUrl.appendingPathComponent(relativePathFrom(normalizedPath: normalizedPath))
    }

    private func relativePathFrom(normalizedPath: String) -> String {
        guard normalizedPath != "/" else { return "" }
        return String(normalizedPath.dropFirst())
    }

    private func buildUrl(path: String, query: [String: String]) -> URL {
        endpointURL(path: path, query: query)
    }

    private func logRequest(method: String, url: URL, headers: [String: String], body: Data?) {
        guard debugLoggingEnabled else { return }
        let bodyText = body.flatMap { String(data: $0, encoding: .utf8) } ?? "<empty>"
        print("🛰 APIClient request: \(method) \(url.absoluteString)")
        if !headers.isEmpty {
            print("🛰 headers: \(redactedHeaders(headers))")
        }
        print("🛰 body: \(bodyText)")
    }

    private func logTokenAudit(method: String, url: URL, token: String?) {
        #if DEBUG
        guard let token else {
            print("🛰 [Auth] request has no token for \(method) \(url.absoluteString)")
            return
        }
        let audience = extractJWTAudience(from: token) ?? "non-JWT"
        let tokenPrefix = String(token.prefix(20))
        print("🛰 [Auth] request token aud for \(method) \(url.absoluteString): \(audience)")
        print("🛰 [Auth] request token preview for \(method) \(url.absoluteString): \(tokenPrefix)...")
        #endif
    }

    private func extractJWTAudience(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if payload.count % 4 != 0 {
            payload += String(repeating: "=", count: 4 - payload.count % 4)
        }
        guard let payloadData = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
              let json = try? JSONSerialization.jsonObject(with: payloadData, options: []),
              let payloadData = json as? [String: Any] else {
            return nil
        }
        if let aud = payloadData["aud"] as? String {
            return aud
        }
        if let audList = payloadData["aud"] as? [String], let first = audList.first {
            return first
        }
        return nil
    }

    private func redactedHeaders(_ headers: [String: String]) -> [String: String] {
        var redacted = headers
        if let auth = headers["Authorization"] {
            let trimmed = auth.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Bearer ") {
                let token = String(trimmed.dropFirst("Bearer ".count))
                redacted["Authorization"] = "Bearer \(String(token.prefix(8)))..."
            } else {
                redacted["Authorization"] = "<redacted>"
            }
        }
        return redacted
    }

    private func logResponse(url: URL, statusCode: Int, body: String?) {
        guard debugLoggingEnabled else { return }
        let preview = body.map { String($0.prefix(4_000)) } ?? "<empty>"
        print("🛰 APIClient response: \(statusCode) \(url.absoluteString)")
        print("🛰 body: \(preview)")
    }

    private func logDecodeFailure(type: String, url: URL, body: String?, error: Error) {
        guard debugLoggingEnabled else { return }
        print("🛰 APIClient decode failure for \(type) at \(url.absoluteString)")
        print("🛰 Decode error: \(error)")
        if let body = body {
            print("🛰 Raw body snippet: \(String(body.prefix(6_000)))")
        }
    }

    private func logError(context: String, error: Error) {
        guard debugLoggingEnabled else { return }
        print("🛰 APIClient error: \(context)")
        print("🛰 Error: \(error)")
    }

    private func logUnauthorizedResponse(method: String, url: URL, body: String?) {
        let preview = body.map { String($0.prefix(4_000)) } ?? "<empty>"
        print("⚠️ APIClient 401 unauthorized (\(method) \(url.absoluteString))")
        print("⚠️ Response body: \(preview)")
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let cancellationCodes: Set<URLError.Code> = [.cancelled]
        if let urlError = error as? URLError {
            return cancellationCodes.contains(urlError.code)
        }
        return false
    }
}
