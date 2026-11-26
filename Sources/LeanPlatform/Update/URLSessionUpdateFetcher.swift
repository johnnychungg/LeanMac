// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import LeanDomain

/// HTTPS-only downloader. A generic User-Agent, no cookies, no cache, no identifiers; every redirect target
/// must be on the host allowlist; size is capped while the data streams in.
public final class URLSessionUpdateFetcher: NSObject, UpdateFetching, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = ["User-Agent": "LeanMac-update-check"]
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public override init() { super.init() }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, UpdateVerifier.isAllowed(url) { completionHandler(request) } else { completionHandler(nil) }
    }

    public func fetchData(_ url: URL, maxBytes: Int) async throws -> Data {
        guard UpdateVerifier.isAllowed(url) else { throw UpdateError.badURL }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            try Self.check(response, maxBytes: maxBytes)
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { throw UpdateError.tooLarge }
            }
            return data
        } catch let error as UpdateError { throw error } catch { throw UpdateError.network(error.localizedDescription) }
    }

    public func download(_ url: URL, into directory: URL, maxBytes: Int) async throws -> URL {
        guard UpdateVerifier.isAllowed(url) else { throw UpdateError.badURL }
        do {
            let (temp, response) = try await session.download(from: url)
            defer { try? FileManager.default.removeItem(at: temp) }
            try Self.check(response, maxBytes: maxBytes)
            let size = (try? temp.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
            guard size <= maxBytes else { throw UpdateError.tooLarge }
            let target = directory.appendingPathComponent("LeanMac-update.zip")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temp, to: target)
            return target
        } catch let error as UpdateError { throw error } catch { throw UpdateError.network(error.localizedDescription) }
    }

    private static func check(_ response: URLResponse, maxBytes: Int) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let url = http.url, UpdateVerifier.isAllowed(url) else { throw UpdateError.network("Unexpected server response") }
        if http.expectedContentLength > Int64(maxBytes) { throw UpdateError.tooLarge }
    }
}
