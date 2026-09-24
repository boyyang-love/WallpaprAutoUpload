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
    case success(String)   // upload ID
    case failed(String)    // error message

    /// 是否可以重新分析
    var canReAnalyze: Bool {
        switch self {
        case .analyzed, .failed: return true
        default: return false
        }
    }

    /// 是否可以重新上传（失败的）
    var canReUpload: Bool {
        if case .failed = self { return true }
        return false
    }

    /// 失败原因
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
    let isPortrait: Bool   // true=MOA, false=PC

    var analysis: ImageAnalysis?
    var status: ImageStatus = .pending
    var uploadProgress: Double = 0

    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool { lhs.id == rhs.id }
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
    var refreshID = UUID()  // 用于强制触发视图刷新
    var errorMessage: String?

    // MARK: - 计算属性

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

    // MARK: - 单张重新分析

    func reAnalyzeImage(id: String, settings: AppSettings) async {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }

        images[idx].status = .analyzing
        images[idx].analysis = nil
        refreshID = UUID()

        let ai = VisionAIClient(
            baseURL: settings.aiBaseURL,
            apiKey: settings.aiAPIKey,
            model: settings.aiModel,
            timeout: settings.aiTimeout
        )

        let prompt = await buildAnalysisPrompt(settings: settings)

        do {
            let analysis = try await ai.analyze(imagePath: images[idx].path, prompt: prompt)
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
              let analysis = images[idx].analysis
        else { return }

        images[idx].status = .uploading
        images[idx].uploadProgress = 0
        refreshID = UUID()

        let api = WallpaperAPIClient(baseURL: settings.apiBaseURL, token: settings.apiToken)
        _ = try? await api.fetchTags()
        _ = try? await api.fetchCategories()
        _ = try? await api.fetchRecommends()

        do {
            let fileName = sanitizeSEOName(analysis.seoName)
            let imgType = images[idx].isPortrait ? "MOA" : "PC"

            let tagIDs = try await withThrowingTaskGroup(of: String.self) { group in
                for tag in analysis.tags {
                    group.addTask { try await api.matchOrCreateTag(tag) }
                }
                var ids: [String] = []
                for try await id in group { ids.append(id) }
                return ids
            }

            let categoryID = try await api.matchOrCreateCategory(analysis.category)

            let recommendIDs = try await withThrowingTaskGroup(of: String.self) { group in
                for rec in analysis.recommend {
                    group.addTask { try await api.matchOrCreateRecommend(rec) }
                }
                var ids: [String] = []
                for try await id in group { ids.append(id) }
                return ids
            }

            let uploadID = try await api.uploadImage(
                filePath: images[idx].path, fileName: fileName, type: imgType,
                quality: settings.uploadQuality, status: settings.uploadStatus,
                rootDir: "IMAGES", dir: settings.uploadDir,
                bucketName: settings.uploadBucket,
                tagIDs: tagIDs, categoryIDs: [categoryID],
                recommendIDs: recommendIDs
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

    private func buildAnalysisPrompt(settings: AppSettings) async -> String {
        let api = WallpaperAPIClient(baseURL: settings.apiBaseURL, token: settings.apiToken)
        var categoryNames: [String] = []
        var tagNames: [String] = []
        var recommendNames: [String] = []
        do {
            let cats = try await api.fetchCategories()
            let tags = try await api.fetchTags()
            let recs = try await api.fetchRecommends()
            categoryNames = cats.map(\.name)
            tagNames = tags.map(\.name)
            recommendNames = recs.map(\.name)
        } catch {}

        let base = """
        你是壁纸分类专家。分析这张图片，返回 JSON 格式：
        {
          "name": "简短的中文图片名称（5-30字）",
          "description": "图片内容简述",
          "seo_name": "SEO友好的中文文件名（用空格分隔，2-8个关键词）",
          "category": "从已有分类列表中选一个最匹配的",
          "tags": ["标签1", "标签2", "标签3"],
          "recommend": ["推荐标签1", "推荐标签2"]
        }
        要求：
        - category 必须从「已有分类」中选择，不能自创
        - tags 3-20个，优先从已有标签中选，没有合适的可自创
        - recommend 1-2个，优先从已有推荐标签中选
        - seo_name 必须是中文，用空格分隔关键词
        - 所有文本用中文
        - 只返回 JSON，不要其他内容
        """

        return base + """

        当前系统已有数据（必须从中选择，不要自创）：
        - 分类（必须从中选1个）：\(categoryNames.isEmpty ? "暂无，请自创" : categoryNames.joined(separator: "、"))
        - 标签（优先从中选，不够可自创）：\(tagNames.isEmpty ? "暂无，请自创" : tagNames.joined(separator: "、"))
        - 推荐标签（优先从中选，不够可自创）：\(recommendNames.isEmpty ? "暂无，请自创" : recommendNames.joined(separator: "、"))
        """
    }

    // MARK: - AI 分析

    func analyzeImages(settings: AppSettings) async {
        guard !selectedIDs.isEmpty else { return }

        isAnalyzing = true
        errorMessage = nil

        let ai = VisionAIClient(
            baseURL: settings.aiBaseURL,
            apiKey: settings.aiAPIKey,
            model: settings.aiModel,
            timeout: settings.aiTimeout
        )

        let dynamicPrompt = await buildAnalysisPrompt(settings: settings)

        for i in images.indices {
            guard selectedIDs.contains(images[i].id) else { continue }
            guard images[i].status != .analyzed else { continue }

            images[i].status = .analyzing

            do {
                let analysis = try await ai.analyze(imagePath: images[i].path, prompt: dynamicPrompt)
                images[i].analysis = analysis
                images[i].status = .analyzed
            } catch {
                images[i].status = .failed("分析失败: \(formatUploadError(error))")
            }

            // 避免请求过快
            if i < images.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        // 强制触发视图刷新（拷贝触发 @Observable 变更通知）
        let snapshot = images
        images = snapshot
        refreshID = UUID()
        isAnalyzing = false
    }

    // MARK: - 上传

    func uploadImages(settings: AppSettings, dryRun: Bool = false, modelContext: ModelContext? = nil) async {
        let toUpload = images.filter { selectedIDs.contains($0.id) && $0.status == .analyzed }
        print("📤 上传开始: 待上传 \(toUpload.count) 张, 干运行=\(dryRun)")
        guard !toUpload.isEmpty else { return }

        isUploading = true
        errorMessage = nil

        let api = WallpaperAPIClient(baseURL: settings.apiBaseURL, token: settings.apiToken)

        // 预加载标签/分类/推荐
        do {
            let tags = try await api.fetchTags()
            let cats = try await api.fetchCategories()
            let recs = try await api.fetchRecommends()
            print("📋 预加载: \(tags.count)标签, \(cats.count)分类, \(recs.count)推荐")
        } catch {
            print("❌ 预加载失败: \(error)")
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
            print("⬆️ 上传 [\(item.fileName)] type=\(item.isPortrait ? "MOA" : "PC") fileName=\(sanitizeSEOName(analysis.seoName))")

            do {
                let fileName = sanitizeSEOName(analysis.seoName)
                let imgType = item.isPortrait ? "MOA" : "PC"

                let tagIDs = try await withThrowingTaskGroup(of: String.self) { group in
                    for tag in analysis.tags {
                        group.addTask { try await api.matchOrCreateTag(tag) }
                    }
                    var ids: [String] = []
                    for try await id in group { ids.append(id) }
                    return ids
                }

                let categoryID = try await api.matchOrCreateCategory(analysis.category)

                let recommendIDs = try await withThrowingTaskGroup(of: String.self) { group in
                    for rec in analysis.recommend {
                        group.addTask { try await api.matchOrCreateRecommend(rec) }
                    }
                    var ids: [String] = []
                    for try await id in group { ids.append(id) }
                    return ids
                }

                let uploadID = try await api.uploadImage(
                    filePath: item.path, fileName: fileName, type: imgType,
                    quality: settings.uploadQuality, status: settings.uploadStatus,
                    rootDir: "IMAGES", dir: settings.uploadDir,
                    bucketName: settings.uploadBucket,
                    tagIDs: tagIDs, categoryIDs: [categoryID],
                    recommendIDs: recommendIDs
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

            // 避免并发过高
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
                    category: img.analysis?.category ?? "",
                    tags: (img.analysis?.tags ?? []).joined(separator: ",")
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

    private func sanitizeSEOName(_ name: String) -> String {
        var result = name.replacingOccurrences(
            of: "[^\\w\\s\\u4e00-\\u9fff]",
            with: " ", options: .regularExpression
        )
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { result = "壁纸" }
        if result.count > 50 { result = String(result.prefix(50)).trimmingCharacters(in: .whitespaces) }
        return result
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
