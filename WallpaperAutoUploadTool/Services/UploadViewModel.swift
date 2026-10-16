//
//  UploadViewModel.swift
//  WallpaperAutoUploadTool
//
//  Created by boyyang on 2026/9/22.
//

import Foundation
import AppKit
import SwiftData

/// 单张图片的处理状态
enum ImageStatus: Equatable {
    case pending
    case analyzing
    case analyzed
    case uploading
    case success(String)
    case failed(String)

    var canReAnalyze: Bool {
        switch self {
        case .analyzed, .failed: return true
        default: return false
        }
    }

    var canReUpload: Bool {
        if case .failed = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let msg) = self {
            let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "上传失败，请重试" : trimmed
        }
        return nil
    }
}

/// 图片列表项
struct ImageItem: Identifiable, Equatable {
    let id: String
    let path: String
    let fileName: String
    let thumbnail: NSImage?
    let isPortrait: Bool

    var analysis: ImageAnalysis?
    var status: ImageStatus = .pending
    var uploadProgress: Double = 0

    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.analysis == rhs.analysis
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class UploadViewModel {
    var selectedFolder: String = ""
    var images: [ImageItem] = []
    var selectedIDs: Set<String> = []
    var isAnalyzing = false
    var isUploading = false
    var refreshID = UUID()
    var errorMessage: String?

    var hasImages: Bool { !images.isEmpty }
    var selectedCount: Int { selectedIDs.count }

    var analyzedCount: Int {
        images.filter { selectedIDs.contains($0.id) && $0.status == .analyzed }.count
    }
    var failedCount: Int {
        images.filter {
            if case .failed = $0.status { return selectedIDs.contains($0.id) }
            return false
        }.count
    }
    var successCount: Int {
        images.filter {
            if case .success = $0.status { return selectedIDs.contains($0.id) }
            return false
        }.count
    }
    var isAllSelected: Bool {
        !images.isEmpty && selectedIDs.count == images.count
    }

    // MARK: - 文件夹选择

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择图片文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        selectedFolder = url.path
        errorMessage = nil
        loadImages(from: url)
    }

    private func loadImages(from folder: URL) {
        let exts: Set<String> = ["jpg", "jpeg", "png", "webp", "bmp"]
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let imageFiles = contents
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        images = imageFiles.compactMap { url -> ImageItem? in
            guard let image = NSImage(contentsOf: url) else { return nil }
            let isPortrait = image.size.height > image.size.width
            return ImageItem(
                id: url.path,
                path: url.path,
                fileName: url.lastPathComponent,
                thumbnail: createThumbnail(image, maxSize: 200),
                isPortrait: isPortrait
            )
        }

        selectedIDs = Set(images.map(\.id))
    }

    private func createThumbnail(_ image: NSImage, maxSize: CGFloat) -> NSImage {
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)
        let newW = size.width * ratio
        let newH = size.height * ratio
        let thumb = NSImage(size: NSSize(width: newW, height: newH))
        thumb.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: newW, height: newH),
                   from: .zero, operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }

    // MARK: - 选择操作

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    func toggleSelectAll() {
        if isAllSelected { selectedIDs.removeAll() }
        else { selectedIDs = Set(images.map(\.id)) }
    }

    // MARK: - API Client 工厂

    private func makeAPIClient(settings: AppSettings) -> APIClient {
        APIClient(baseURL: settings.apiBaseURL, token: settings.apiToken)
    }

    // MARK: - 单张重新分析

    func reAnalyzeImage(id: String, settings: AppSettings) async {
        guard let idx = images.firstIndex(where: { $0.id == id }),
              let workflow = settings.workflow else { return }

        images[idx].status = .analyzing
        images[idx].analysis = nil
        refreshID = UUID()

        let ai = VisionAIClient(
            baseURL: settings.aiBaseURL,
            apiKey: settings.aiAPIKey,
            model: settings.aiModel,
            timeout: settings.aiTimeout
        )

        let prompt = await buildAnalysisPrompt(settings: settings, workflow: workflow)

        do {
            let analysis = try await ai.analyze(imagePath: images[idx].path, prompt: prompt, outputFields: workflow.ai.outputFields)
            images[idx].analysis = analysis
            images[idx].status = .analyzed
        } catch {
            images[idx].status = .failed("分析失败: \(formatUploadError(error))")
        }

        refreshID = UUID()
    }

    // MARK: - 单张重新上传

    func reUploadImage(id: String, settings: AppSettings) async {
        guard let idx = images.firstIndex(where: { $0.id == id }),
              let analysis = images[idx].analysis,
              let workflow = settings.workflow
        else { return }

        images[idx].status = .uploading
        images[idx].uploadProgress = 0
        refreshID = UUID()

        let api = makeAPIClient(settings: settings)

        do {
            let uploadFields = try await resolveUploadFields(
                analysis: analysis, workflow: workflow,
                settings: settings, api: api,
                isPortrait: images[idx].isPortrait
            )

            let uploadID = try await api.uploadImage(
                uploadPath: workflow.upload.path,
                filePath: images[idx].path,
                fields: uploadFields
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.images[idx].uploadProgress = progress
                }
            }

            images[idx].status = .success(uploadID)
        } catch {
            images[idx].status = .failed(formatUploadError(error))
        }

        refreshID = UUID()
    }

    // MARK: - 构建分析 Prompt

    private func buildAnalysisPrompt(settings: AppSettings, workflow: WorkflowConfig) async -> String {
        let api = makeAPIClient(settings: settings)

        var existingDataParts: [String] = []
        for entity in workflow.entities {
            do {
                let records = try await api.listEntities(path: entity.listPath)
                let names = records.map(\.name)
                if !names.isEmpty {
                    existingDataParts.append("- \(entity.name)（优先从中选）：\(names.joined(separator: "、"))")
                }
            } catch {}
        }

        let existingData = existingDataParts.isEmpty ? nil : existingDataParts.joined(separator: "\n")
        return workflow.generateAIPrompt(existingData: existingData)
    }

    // MARK: - AI 分析

    func analyzeImages(settings: AppSettings) async {
        guard !selectedIDs.isEmpty, let workflow = settings.workflow else { return }

        isAnalyzing = true
        errorMessage = nil

        let ai = VisionAIClient(
            baseURL: settings.aiBaseURL,
            apiKey: settings.aiAPIKey,
            model: settings.aiModel,
            timeout: settings.aiTimeout
        )

        let dynamicPrompt = await buildAnalysisPrompt(settings: settings, workflow: workflow)

        for i in images.indices {
            guard selectedIDs.contains(images[i].id) else { continue }
            guard images[i].status != .analyzed else { continue }

            images[i].status = .analyzing

            do {
                let analysis = try await ai.analyze(imagePath: images[i].path, prompt: dynamicPrompt, outputFields: workflow.ai.outputFields)
                print("🔍 分析结果 [\(images[i].fileName)]:")
                for field in analysis.orderedFields {
                    print("   \(field.key) = \(field.value)")
                }
                images[i].analysis = analysis
                images[i].status = .analyzed
            } catch {
                images[i].status = .failed("分析失败: \(formatUploadError(error))")
            }

            if i < images.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        let snapshot = images
        images = snapshot
        refreshID = UUID()
        isAnalyzing = false
    }

    // MARK: - 上传

    func uploadImages(settings: AppSettings, dryRun: Bool = false, modelContext: ModelContext? = nil) async {
        guard let workflow = settings.workflow else { return }
        let toUpload = images.filter { selectedIDs.contains($0.id) && $0.status == .analyzed }
        print("📤 上传开始: 待上传 \(toUpload.count) 张, 干运行=\(dryRun)")
        guard !toUpload.isEmpty else { return }

        isUploading = true
        errorMessage = nil

        let api = makeAPIClient(settings: settings)

        // 预加载所有实体列表（缓存）
        for entity in workflow.entities {
            _ = try? await api.listEntities(path: entity.listPath)
        }

        for item in toUpload {
            guard let idx = images.firstIndex(where: { $0.id == item.id }),
                  let analysis = item.analysis
            else { continue }

            if dryRun {
                images[idx].status = .success("试运行")
                continue
            }

            images[idx].status = .uploading
            images[idx].uploadProgress = 0

            do {
                let uploadFields = try await resolveUploadFields(
                    analysis: analysis, workflow: workflow,
                    settings: settings, api: api,
                    isPortrait: item.isPortrait
                )

                let uploadID = try await api.uploadImage(
                    uploadPath: workflow.upload.path,
                    filePath: item.path,
                    fields: uploadFields
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.images[idx].uploadProgress = progress
                    }
                }

                images[idx].status = .success(uploadID)
                print("✅ 上传成功 [\(item.fileName)] ID: \(uploadID)")
            } catch {
                images[idx].status = .failed(formatUploadError(error))
                print("❌ 上传失败 [\(item.fileName)]: \(error)")
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // 保存历史记录
        if let ctx = modelContext {
            let items = images.filter { selectedIDs.contains($0.id) }.map { img -> UploadRecordItem in
                let statusStr: String
                let uploadID: String
                let errorMsg: String
                switch img.status {
                case .success(let id): statusStr = "success"; uploadID = id; errorMsg = ""
                case .failed(let msg): statusStr = "failed"; uploadID = ""; errorMsg = msg
                default: statusStr = dryRun ? "dry_run" : "pending"; uploadID = ""; errorMsg = ""
                }
                return UploadRecordItem(
                    fileName: img.fileName, filePath: img.path,
                    imageType: img.isPortrait ? "MOA" : "PC",
                    status: statusStr, uploadID: uploadID, errorMessage: errorMsg,
                    category: img.analysis?.string("category") ?? "",
                    tags: (img.analysis?.array("tags") ?? []).joined(separator: ",")
                )
            }
            let record = UploadRecord(
                folderPath: selectedFolder, date: .now,
                totalCount: items.count,
                successCount: items.filter { $0.status == "success" }.count,
                failedCount: items.filter { $0.status == "failed" }.count,
                items: items
            )
            ctx.insert(record)
            try? ctx.save()
        }

        isUploading = false
    }

    // MARK: - Resolve Upload Fields

    /// 根据工作流配置解析上传字段
    private func resolveUploadFields(
        analysis: ImageAnalysis,
        workflow: WorkflowConfig,
        settings: AppSettings,
        api: APIClient,
        isPortrait: Bool
    ) async throws -> [String: String] {
        var fields: [String: String] = [:]
        print("📋 resolveUploadFields: entities=\(workflow.entities.map(\.name)) analysisFields=\(analysis.orderedFields.map(\.key))")

        for (fieldName, source) in workflow.upload.fields {
            switch source.source {
            case "file":
                // 文件字段在 uploadImage 中单独处理
                continue

            case "ai":
                let aiField = source.field ?? fieldName
                if let sep = source.separator {
                    fields[fieldName] = analysis.array(aiField).joined(separator: sep)
                } else {
                    fields[fieldName] = analysis.string(aiField)
                }

            case "entity_ids":
                let aiField = source.field ?? fieldName
                let entityName = source.entity ?? source.field ?? fieldName
                print("🔗 entity_ids: fieldName=\(fieldName) aiField=\(aiField) entityName=\(entityName)")
                // 找到对应的实体配置：先按 entity 名找，找不到再按 outputField 的 entityName 找
                var entityConfig = workflow.entities.first(where: { $0.name == entityName })
                if entityConfig == nil {
                    // 回退：用 AI outputField 的 entityName 匹配
                    if let outputField = workflow.ai.outputFields.first(where: { $0.name == aiField }),
                       let fallbackEntity = outputField.entityName {
                        entityConfig = workflow.entities.first(where: { $0.name == fallbackEntity })
                        if entityConfig != nil {
                            print("🔗 回退到 outputField.entityName=\(fallbackEntity)")
                        }
                    }
                }
                guard let entityConfig else {
                    print("⚠️ 未找到实体配置: \(entityName)，可用: \(workflow.entities.map(\.name))")
                    fields[fieldName] = analysis.string(aiField)
                    continue
                }

                // 尝试数组类型（如 tags），否则按字符串处理
                let arrayValue = analysis.array(aiField)
                print("🔗 \(aiField) arrayValue=\(arrayValue)")
                if !arrayValue.isEmpty {
                    // 数组类型：批量匹配或创建
                    var ids: [String] = []
                    for name in arrayValue {
                        let id = try await api.matchOrCreate(
                            name: name,
                            listPath: entityConfig.listPath,
                            createPath: entityConfig.createPath,
                            createBody: entityConfig.createBody
                        )
                        ids.append(id)
                    }
                    fields[fieldName] = ids.joined(separator: source.separator ?? ",")
                } else {
                    let stringValue = analysis.string(aiField)
                    if !stringValue.isEmpty {
                        // 字符串类型：单个匹配或创建
                        let id = try await api.matchOrCreate(
                            name: stringValue,
                            listPath: entityConfig.listPath,
                            createPath: entityConfig.createPath,
                            createBody: entityConfig.createBody
                        )
                        fields[fieldName] = id
                    }
                }

            case "setting":
                let key = source.key ?? fieldName
                fields[fieldName] = resolveSetting(key: key, settings: settings, isPortrait: isPortrait)

            case "value":
                fields[fieldName] = source.value ?? ""

            default:
                break
            }
        }

        return fields
    }

    /// 从 AppSettings 读取通用设置值
    private func resolveSetting(key: String, settings: AppSettings, isPortrait: Bool) -> String {
        switch key {
        case "apiBaseURL": return settings.apiBaseURL
        case "apiToken": return settings.apiToken
        case "aiBaseURL": return settings.aiBaseURL
        case "aiAPIKey": return settings.aiAPIKey
        case "aiModel": return settings.aiModel
        case "uploadQuality": return "\(settings.uploadQuality)"
        case "uploadStatus": return "\(settings.uploadStatus)"
        case "uploadDir": return settings.uploadDir
        case "uploadBucket": return settings.uploadBucket
        case "uploadRootDir": return settings.uploadRootDir
        case "imageType": return isPortrait ? "MOA" : "PC"
        default: return ""
        }
    }

    private func formatUploadError(_ error: Error) -> String {
        let desc = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !desc.isEmpty { return desc }
        if let apiErr = error as? APIError { return apiErr.errorDescription ?? "未知 API 错误" }
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet: return "网络未连接"
            case .timedOut: return "请求超时"
            case .cannotFindHost, .dnsLookupFailed: return "无法解析服务器地址"
            case .cannotConnectToHost: return "无法连接服务器"
            default: return "网络错误: \(urlErr.code.rawValue)"
            }
        }
        return "未知错误 (\(type(of: error)))"
    }
}
