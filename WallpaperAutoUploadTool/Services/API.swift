//
//  API.swift
//  WallpaperAutoUploadTool
//
//  Created by boyyang on 2026/9/22.
//

import Foundation
import AppKit

// MARK: - Models

struct PaginatedRecord: Codable {
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

struct ImageAnalysis: Equatable {
    /// 字段类型：字符串或字符串数组
    enum FieldValue: Equatable {
        case string(String)
        case array([String])

        var isEmpty: Bool {
            switch self {
            case .string(let s): return s.isEmpty
            case .array(let a): return a.isEmpty
            }
        }
    }

    /// 有序字段列表（保持插入顺序用于 UI 显示）
    private(set) var orderedFields: [(key: String, value: FieldValue)]

    /// 字段字典（用于快速查找）
    private var fieldMap: [String: FieldValue]

    init(fields: [String: Any]) {
        var ordered: [(String, FieldValue)] = []
        var map: [String: FieldValue] = [:]
        for (k, v) in fields {
            let fv: FieldValue
            if let arr = v as? [String] {
                fv = .array(arr)
            } else {
                fv = .string("\(v)")
            }
            ordered.append((k, fv))
            map[k] = fv
        }
        self.orderedFields = ordered.sorted { $0.0 < $1.0 }
        self.fieldMap = map
    }

    static func == (lhs: ImageAnalysis, rhs: ImageAnalysis) -> Bool {
        guard lhs.orderedFields.count == rhs.orderedFields.count else { return false }
        for (l, r) in zip(lhs.orderedFields, rhs.orderedFields) {
            if l.key != r.key || l.value != r.value { return false }
        }
        return true
    }

    func string(_ key: String) -> String {
        if case .string(let s) = fieldMap[key] { return s }
        return ""
    }

    func array(_ key: String) -> [String] {
        if case .array(let a) = fieldMap[key] { return a }
        return []
    }

    func valueForField(_ fieldName: String, separator: String? = nil) -> String {
        if let sep = separator {
            return array(fieldName).joined(separator: sep)
        }
        return string(fieldName)
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

// MARK: - Generic API Client

final class APIClient {
    private let baseURL: String
    private let client: URLSession

    init(baseURL: String, token: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["Authorization": token]
        self.client = URLSession(configuration: config)
    }

    // MARK: - Entity CRUD

    /// 获取实体列表（标签/分类/推荐等通用接口）
    func listEntities(path: String) async throws -> [PaginatedRecord] {
        do {
            let resp: APIResponse<PaginatedData<PaginatedRecord>> = try await get(path, params: ["page": "1", "limit": "10000"])
            return resp.data?.records ?? []
        } catch {
            print("⚠️ listEntities(\(path)) 失败: \(error)")
            return []
        }
    }

    /// 创建实体
    @discardableResult
    func createEntity(path: String, body: [String: String]) async throws -> Data {
        try await postRaw(path, body: body)
    }

    /// 匹配已有实体或创建新实体，返回 ID
    func matchOrCreate(name: String, listPath: String, createPath: String, createBody: [String: String]) async throws -> String {
        let existing = try await listEntities(path: listPath)
        if let match = existing.first(where: { $0.name == name }) {
            return match.id
        }
        // 构建请求体，替换 {{name}} 占位符
        var body = createBody
        for (key, value) in body {
            body[key] = value.replacingOccurrences(of: "{{name}}", with: name)
        }
        do {
            try await createEntity(path: createPath, body: body)
        } catch {
            print("⚠️ createEntity(\(createPath)) 失败: \(error)")
            return ""
        }
        // 重新查询获取 ID
        let refreshed = try await listEntities(path: listPath)
        return refreshed.first(where: { $0.name == name })?.id ?? ""
    }

    // MARK: - Image Upload

    func uploadImage(
        uploadPath: String,
        filePath: String,
        fields: [String: String],
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let imageData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let ext = (filePath as NSString).pathExtension.lowercased()
        let mime = ext == "png" ? "image/png" : ext == "webp" ? "image/webp" : "image/jpeg"
        let fileName = (filePath as NSString).lastPathComponent

        print("📤 上传字段: \(fields)")

        let boundary = "----Boundary\(UUID().uuidString)"
        let body = buildMultipartBody(fields: fields, fileData: imageData,
                                      fileName: fileName, mimeType: mime)(boundary)

        var request = URLRequest(url: URL(string: "\(baseURL)\(uploadPath)")!)
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

    // MARK: - Private helpers

    private func get<T: Codable>(_ path: String, params: [String: String]? = nil) async throws -> T {
        var components = URLComponents(string: baseURL + path)!
        if let params = params {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let url = components.url!
        print("🌐 GET \(url)")
        let (data, response) = try await client.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let raw = String(data: data, encoding: .utf8) ?? ""
        print("📥 响应 [\(statusCode)]: \(raw.prefix(200))")

        guard (200...299).contains(statusCode) else {
            throw APIError.serverError(statusCode, raw.isEmpty ? nil : raw)
        }
        guard !data.isEmpty else {
            throw APIError.serverError(statusCode, "空响应")
        }
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

    func analyze(imagePath: String, prompt: String, outputFields: [WorkflowConfig.OutputField]) async throws -> ImageAnalysis {
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

        let rawResponse = String(data: data, encoding: .utf8) ?? "<binary>"
        print("🤖 AI 原始响应: \(rawResponse.prefix(500))")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else {
            return ImageAnalysis(fields: [:])
        }

        var content = message["content"] as? String ?? ""
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let reasoning = message["reasoning_content"] as? String {
            content = reasoning
        }

        return parseAIResponse(content, outputFields: outputFields)
    }

    private func parseAIResponse(_ content: String, outputFields: [WorkflowConfig.OutputField]) -> ImageAnalysis {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try extracting from markdown code block
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
                if let result = parseJSONString(candidate, outputFields: outputFields) {
                    return result
                }
            }
        }

        // Try direct parse
        if let result = parseJSONString(trimmed, outputFields: outputFields) {
            return result
        }

        // Try finding JSON object from the end
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
                if let result = parseJSONString(candidate, outputFields: outputFields) {
                    return result
                }
            }
            end = start
        }

        return ImageAnalysis(fields: [:])
    }

    private func parseJSONString(_ str: String, outputFields: [WorkflowConfig.OutputField]) -> ImageAnalysis? {
        guard let data = str.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var fields: [String: Any] = [:]
        for field in outputFields {
            guard let value = json[field.name] else { continue }
            var stored = value
            // 数组字段：超过 max_items 时截断（AI 不总是遵守数量要求）
            if field.type == "array", let max = field.maxItems {
                var arr: [String]? = nil
                if let a = value as? [String] {
                    arr = a
                } else if let a = value as? [Any] {
                    arr = a.map { "\($0)" }
                }
                if let a = arr {
                    if a.count > max {
                        print("✂️ \(field.name) 返回 \(a.count) 个，超出上限 \(max)，截断")
                        stored = Array(a.prefix(max))
                    } else {
                        stored = a
                    }
                }
                // 非数组值保持原样，交由字符串分支处理
            }
            fields[field.name] = stored
        }
        guard !fields.isEmpty else {
            print("⚠️ parseJSONString: 没有匹配到任何 outputFields")
            return nil
        }
        print("✅ parseJSONString: 提取到 \(fields.count) 个字段: \(fields.keys.sorted())")
        return ImageAnalysis(fields: fields)
    }
}
