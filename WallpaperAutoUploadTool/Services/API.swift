//
//  API.swift
//  WallpaperAutoUploadTool
//
//  Created by boyyang on 2026/9/22.
//

import Foundation
import AppKit

// MARK: - Models

struct TagRecord: Codable {
    let id: String
    let name: String
}

struct CategoryRecord: Codable {
    let id: String
    let name: String
}

struct RecommendRecord: Codable {
    let id: String
    let name: String
}

struct APIResponse<T: Codable>: Codable {
    let code: Int
    let msg: String?
    let data: T?
}

struct PaginatedData<T: Codable>: Codable {
    let records: [T]
}

struct UploadData: Codable {
    let id: String?
}

struct ImageAnalysis: Codable {
    var name: String
    var description: String
    var seoName: String
    var category: String
    var tags: [String]
    var recommend: [String]

    enum CodingKeys: String, CodingKey {
        case name, description, category, tags, recommend
        case seoName = "seo_name"
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case serverError(Int, String?)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无效的服务器响应"
        case .serverError(let code, let msg): return "服务器错误 (\(code)): \(msg ?? "未知")"
        case .decodingError(let err): return "数据解析失败: \(err.localizedDescription)"
        }
    }
}

// MARK: - Upload Progress Delegate

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    var progressHandler: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<(Data, URLResponse), any Error>?
    private var receivedData = Data()
    private var task: URLSessionDataTask?

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        let progress = totalBytesExpectedToSend > 0
            ? Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            : 0
        progressHandler?(min(progress, 1.0))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else if let response = task.response {
            continuation?.resume(returning: (receivedData, response))
        }
        continuation = nil
    }

    func upload(request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let t = session.dataTask(with: request)
            self.task = t
            t.resume()
        }
    }
}

// MARK: - Wallpaper API Client

final class WallpaperAPIClient {
    private let baseURL: String
    private let client: URLSession
    private var cachedTags: [TagRecord] = []
    private var cachedCategories: [CategoryRecord] = []
    private var cachedRecommends: [RecommendRecord] = []

    init(baseURL: String, token: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["Authorization": token]
        self.client = URLSession(configuration: config)
    }

    // MARK: Fetch existing data

    func fetchTags() async throws -> [TagRecord] {
        if !cachedTags.isEmpty { return cachedTags }
        let resp: APIResponse<PaginatedData<TagRecord>> = try await get("/tag/info", params: ["page": "1", "limit": "10000"])
        cachedTags = resp.data?.records ?? []
        return cachedTags
    }

    func fetchCategories() async throws -> [CategoryRecord] {
        if !cachedCategories.isEmpty { return cachedCategories }
        let resp: APIResponse<PaginatedData<CategoryRecord>> = try await get("/category/info", params: ["page": "1", "limit": "10000"])
        cachedCategories = resp.data?.records ?? []
        return cachedCategories
    }

    func fetchRecommends() async throws -> [RecommendRecord] {
        if !cachedRecommends.isEmpty { return cachedRecommends }
        let resp: APIResponse<PaginatedData<RecommendRecord>> = try await get("/recommend/info", params: ["page": "1", "limit": "10000"])
        cachedRecommends = resp.data?.records ?? []
        return cachedRecommends
    }

    // MARK: Match or create

    func matchOrCreateTag(_ name: String) async throws -> String {
        let tags = try await fetchTags()
        if let existing = tags.first(where: { $0.name == name }) { return existing.id }
        return try await createTag(name).id
    }

    func matchOrCreateCategory(_ name: String) async throws -> String {
        let cats = try await fetchCategories()
        if let existing = cats.first(where: { $0.name == name }) { return existing.id }
        return try await createCategory(name).id
    }

    func matchOrCreateRecommend(_ name: String) async throws -> String {
        let recs = try await fetchRecommends()
        if let existing = recs.first(where: { $0.name == name }) { return existing.id }
        return try await createRecommend(name).id
    }

    // MARK: Create

    private func createTag(_ name: String) async throws -> TagRecord {
        try await postRaw("/tag/create", body: [
            "name": name, "type": "wallpaper", "sort": "0"
        ])
        cachedTags = []
        let tags = try await fetchTags()
        return tags.first(where: { $0.name == name }) ?? TagRecord(id: "", name: name)
    }

    private func createCategory(_ name: String) async throws -> CategoryRecord {
        try await postRaw("/category/create", body: [
            "name": name, "cover_id": "", "cover": "", "sort": "0", "web": "true", "moa": "true"
        ])
        cachedCategories = []
        let cats = try await fetchCategories()
        return cats.first(where: { $0.name == name }) ?? CategoryRecord(id: "", name: name)
    }

    private func createRecommend(_ name: String) async throws -> RecommendRecord {
        try await postRaw("/recommend/create", body: [
            "name": name, "sort": "0"
        ])
        cachedRecommends = []
        let recs = try await fetchRecommends()
        return recs.first(where: { $0.name == name }) ?? RecommendRecord(id: "", name: name)
    }

    // MARK: Upload

    func uploadImage(
        filePath: String, fileName: String, type: String,
        quality: Int, status: Int, rootDir: String, dir: String,
        bucketName: String, tagIDs: [String],
        categoryIDs: [String], recommendIDs: [String],
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let imageData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let ext = (filePath as NSString).pathExtension.lowercased()
        let mime = ext == "png" ? "image/png" : ext == "webp" ? "image/webp" : "image/jpeg"
        let uploadName = fileName + "." + ext

        let fields: [String: String] = [
            "file_name": fileName, "root_dir": rootDir, "dir": dir,
            "bucket_name": bucketName, "quality": "\(quality)", "status": "\(status)",
            "type": type, "tags": tagIDs.joined(separator: ","),
            "category": categoryIDs.joined(separator: ","),
            "recommend": recommendIDs.joined(separator: ","),
            "group": "", "album": "",
        ]

        let boundary = "----Boundary\(UUID().uuidString)"
        let body = buildMultipartBody(fields: fields, fileData: imageData,
                                      fileName: uploadName, mimeType: mime)(boundary)

        var request = URLRequest(url: URL(string: "\(baseURL)/image/upload")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse

        if let progressHandler {
            let delegate = UploadProgressDelegate()
            delegate.progressHandler = progressHandler
            let session = URLSession(configuration: client.configuration, delegate: delegate, delegateQueue: nil)
            (data, response) = try await delegate.upload(request: request, session: session)
        } else {
            (data, response) = try await client.data(for: request)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let msg = String(data: data, encoding: .utf8)
            throw APIError.serverError(code, msg)
        }

        // 先检查响应是否是有效 JSON
        let raw = String(data: data, encoding: .utf8) ?? "<binary>"
        print("🔍 上传原始响应: \(raw.prefix(300))")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.serverError(0, "服务器返回非JSON: \(raw.prefix(200))")
        }

        let code = json["code"] as? Int ?? 0
        let msg = json["msg"] as? String
        if code == 1 {
            progressHandler?(1.0)
            let dataObj = json["data"] as? [String: Any]
            return dataObj?["id"] as? String ?? ""
        }
        throw APIError.serverError(code, msg)
    }

    // MARK: Private helpers

    private func get<T: Codable>(_ path: String, params: [String: String]? = nil) async throws -> T {
        var components = URLComponents(string: baseURL + path)!
        if let params = params {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let (data, _) = try await client.data(from: components.url!)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Codable>(_ path: String, body: [String: String]) async throws -> T {
        let data = try await postRaw(path, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func postRaw(_ path: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await client.data(for: request)
        return data
    }

    private func buildMultipartBody(
        fields: [String: String], fileData: Data,
        fileName: String, mimeType: String
    ) -> (String) -> Data {
        return { boundary in
            var body = Data()
            let prefix = "--\(boundary)\r\n"
            let separator = "\r\n"

            for (key, value) in fields {
                body.append(prefix.data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\(separator)".data(using: .utf8)!)
            }

            body.append(prefix.data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append(separator.data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            return body
        }
    }
}

private struct EmptyData: Codable {}

// MARK: - Vision AI Client

final class VisionAIClient {
    private let baseURL: String
    private let apiKey: String
    private let model: String
    private let client: URLSession

    init(baseURL: String, apiKey: String, model: String, timeout: Int = 60) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(timeout)
        self.client = URLSession(configuration: config)
    }

    func analyze(imagePath: String, prompt: String) async throws -> ImageAnalysis {
        let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        let b64 = imageData.base64EncodedString()
        let ext = (imagePath as NSString).pathExtension.lowercased()
        let mime = ext == "png" ? "image/png" : ext == "webp" ? "image/webp" : "image/jpeg"

        let payload: [String: Any] = [
            "model": model,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(b64)"]],
                ] as [[String: Any]]
            ] as [String: Any]],
            "max_completion_tokens": 2048,
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
        ]

        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await client.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else {
            return ImageAnalysis(name: "", description: "", seoName: "", category: "", tags: [], recommend: [])
        }

        var content = message["content"] as? String ?? ""
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let reasoning = message["reasoning_content"] as? String {
            content = reasoning
        }

        let analysis = try parseAIResponse(content)
        return analysis
    }

    private func parseAIResponse(_ content: String) throws -> ImageAnalysis {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 尝试从 markdown 代码块提取
        if trimmed.contains("```") {
            let lines = trimmed.components(separatedBy: "\n")
            var jsonLines: [String] = []
            var inBlock = false
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") && !inBlock {
                    inBlock = true; continue
                } else if line.trimmingCharacters(in: .whitespaces) == "```" && inBlock {
                    break
                } else if inBlock {
                    jsonLines.append(line)
                }
            }
            if !jsonLines.isEmpty {
                let candidate = jsonLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if let result = try? JSONDecoder().decode(ImageAnalysis.self, from: Data(candidate.utf8)) {
                    return result
                }
            }
        }

        // 直接解析
        if let result = try? JSONDecoder().decode(ImageAnalysis.self, from: Data(trimmed.utf8)) {
            return result
        }

        // 从后往前找完整的 JSON 对象
        var end = trimmed.endIndex
        while end > trimmed.startIndex {
            guard let lastBrace = trimmed[..<end].lastIndex(of: "}") else { break }
            var depth = 0
            var start = lastBrace
            while start >= trimmed.startIndex {
                if trimmed[start] == "}" { depth += 1 }
                else if trimmed[start] == "{" { depth -= 1 }
                if depth == 0 { break }
                start = trimmed.index(before: start)
            }
            if depth == 0 {
                let candidate = String(trimmed[start...lastBrace])
                if let result = try? JSONDecoder().decode(ImageAnalysis.self, from: Data(candidate.utf8)) {
                    return result
                }
            }
            end = start
        }

        return ImageAnalysis(name: "", description: "", seoName: "", category: "", tags: [], recommend: [])
    }
}
