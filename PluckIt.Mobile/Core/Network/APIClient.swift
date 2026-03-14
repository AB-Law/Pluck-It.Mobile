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
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        if let token = await tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        logRequest(method: method, url: url, headers: request.allHTTPHeaderFields ?? [:], body: body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            let bodyText = String(data: data, encoding: .utf8)
            logResponse(url: url, statusCode: httpResponse.statusCode, body: bodyText)

            guard (200 ... 299).contains(httpResponse.statusCode) else {
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
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let token = await tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        logRequest(method: method, url: url, headers: request.allHTTPHeaderFields ?? [:], body: body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            let bodyText = String(data: data, encoding: .utf8)
            logResponse(url: url, statusCode: httpResponse.statusCode, body: bodyText)

            guard (200 ... 299).contains(httpResponse.statusCode) else {
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
        timeout: TimeInterval = 60
    ) async throws -> T {
        let url = buildUrl(path: path, query: [:])
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = await tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        logRequest(method: "POST", url: url, headers: request.allHTTPHeaderFields ?? [:], body: nil)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            let bodyText = String(data: data, encoding: .utf8)
            logResponse(url: url, statusCode: httpResponse.statusCode, body: bodyText)
            guard (200 ... 299).contains(httpResponse.statusCode) else {
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
        if let token = await tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
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
            print("🛰 headers: \(headers)")
        }
        print("🛰 body: \(bodyText)")
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

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let cancellationCodes: Set<URLError.Code> = [.cancelled]
        if let urlError = error as? URLError {
            return cancellationCodes.contains(urlError.code)
        }
        return false
    }
}
