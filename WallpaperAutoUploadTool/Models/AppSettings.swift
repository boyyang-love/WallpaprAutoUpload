//
//  AppSettings.swift
//  WallpaperAutoUploadTool
//
//  Created by boyyang on 2026/9/22.
//

import Foundation

/// 应用设置，使用 UserDefaults 持久化
@Observable
final class AppSettings {

    // MARK: - 后台 API

    var apiBaseURL: String {
        didSet { UserDefaults.standard.set(apiBaseURL, forKey: Keys.apiBaseURL) }
    }
    var apiToken: String {
        didSet { UserDefaults.standard.set(apiToken, forKey: Keys.apiToken) }
    }

    // MARK: - AI 模型

    var aiBaseURL: String {
        didSet { UserDefaults.standard.set(aiBaseURL, forKey: Keys.aiBaseURL) }
    }
    var aiAPIKey: String {
        didSet { UserDefaults.standard.set(aiAPIKey, forKey: Keys.aiAPIKey) }
    }
    var aiModel: String {
        didSet { UserDefaults.standard.set(aiModel, forKey: Keys.aiModel) }
    }
    var aiTimeout: Int {
        didSet { UserDefaults.standard.set(aiTimeout, forKey: Keys.aiTimeout) }
    }

    // MARK: - 通用上传配置

    var uploadQuality: Int {
        didSet { UserDefaults.standard.set(uploadQuality, forKey: Keys.uploadQuality) }
    }
    var uploadStatus: Int {
        didSet { UserDefaults.standard.set(uploadStatus, forKey: Keys.uploadStatus) }
    }
    var uploadDir: String {
        didSet { UserDefaults.standard.set(uploadDir, forKey: Keys.uploadDir) }
    }
    var uploadBucket: String {
        didSet { UserDefaults.standard.set(uploadBucket, forKey: Keys.uploadBucket) }
    }
    var uploadRootDir: String {
        didSet { UserDefaults.standard.set(uploadRootDir, forKey: Keys.uploadRootDir) }
    }

    // MARK: - 工作流配置

    /// 当前选中的工作流 JSON 字符串
    var selectedWorkflow: String {
        didSet { UserDefaults.standard.set(selectedWorkflow, forKey: Keys.selectedWorkflow) }
    }

    /// 解析后的工作流配置（只读计算属性）
    var workflow: WorkflowConfig? {
        guard let data = selectedWorkflow.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return WorkflowConfig(json: json)
    }

    /// 是否已完成初始配置（至少填了 API 地址和 Token）
    var isConfigured: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !apiToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard

        defaults.register(defaults: [
            Keys.apiBaseURL: "",
            Keys.apiToken: "",
            Keys.aiBaseURL: "",
            Keys.aiAPIKey: "",
            Keys.aiModel: "",
            Keys.aiTimeout: 60,
            Keys.uploadQuality: 5,
            Keys.uploadStatus: 1,
            Keys.uploadDir: "",
            Keys.uploadBucket: "",
            Keys.uploadRootDir: "IMAGES",
        ])

        self.apiBaseURL = defaults.string(forKey: Keys.apiBaseURL) ?? ""
        self.apiToken = defaults.string(forKey: Keys.apiToken) ?? ""
        self.aiBaseURL = defaults.string(forKey: Keys.aiBaseURL) ?? ""
        self.aiAPIKey = defaults.string(forKey: Keys.aiAPIKey) ?? ""
        self.aiModel = defaults.string(forKey: Keys.aiModel) ?? ""
        self.aiTimeout = defaults.integer(forKey: Keys.aiTimeout)
        self.uploadQuality = defaults.integer(forKey: Keys.uploadQuality)
        self.uploadStatus = defaults.integer(forKey: Keys.uploadStatus)
        self.uploadDir = defaults.string(forKey: Keys.uploadDir) ?? ""
        self.uploadBucket = defaults.string(forKey: Keys.uploadBucket) ?? ""
        self.uploadRootDir = defaults.string(forKey: Keys.uploadRootDir) ?? "IMAGES"

        // 加载工作流配置，默认使用壁纸上传模板
        if let saved = defaults.string(forKey: Keys.selectedWorkflow), !saved.isEmpty,
           let data = saved.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           WorkflowConfig(json: json) != nil {
            self.selectedWorkflow = saved
        } else if let config = TemplateStore.wallpaper {
            self.selectedWorkflow = Self.serializeConfig(config)
        } else {
            self.selectedWorkflow = "{}"
        }
    }

    /// 设置工作流为指定配置
    func setWorkflow(_ config: WorkflowConfig) {
        self.selectedWorkflow = Self.serializeConfig(config)
    }

    /// 将 WorkflowConfig 序列化为 JSON 字符串
    static func serializeConfig(_ config: WorkflowConfig) -> String {
        var json: [String: Any] = [
            "name": config.name,
            "description": config.description,
            "version": config.version,
        ]

        // AI
        json["ai"] = [
            "output_fields": config.ai.outputFields.map { f -> [String: Any] in
                var d: [String: Any] = ["name": f.name, "type": f.type, "description": f.description]
                if let e = f.entityName { d["entity"] = e }
                if let v = f.minItems { d["min_items"] = v }
                if let v = f.maxItems { d["max_items"] = v }
                return d
            }
        ]

        // Entities
        var entitiesJson: [String: Any] = [:]
        for e in config.entities {
            entitiesJson[e.name] = [
                "list_path": e.listPath,
                "create_path": e.createPath,
                "create_body": e.createBody,
            ]
        }
        json["entities"] = entitiesJson

        // Upload
        var fieldsJson: [String: Any] = [:]
        for (fName, fSource) in config.upload.fields {
            var d: [String: Any] = ["source": fSource.source]
            if let v = fSource.field { d["field"] = v }
            if let v = fSource.key { d["key"] = v }
            if let v = fSource.value { d["value"] = v }
            if let v = fSource.separator { d["separator"] = v }
            if let v = fSource.entity { d["entity"] = v }
            fieldsJson[fName] = d
        }
        json["upload"] = [
            "path": config.upload.path,
            "fields": fieldsJson,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

// MARK: - Keys

private enum Keys {
    static let apiBaseURL = "api_base_url"
    static let apiToken = "api_token"
    static let aiBaseURL = "ai_base_url"
    static let aiAPIKey = "ai_api_key"
    static let aiModel = "ai_model"
    static let aiTimeout = "ai_timeout"
    static let uploadQuality = "upload_quality"
    static let uploadStatus = "upload_status"
    static let uploadDir = "upload_dir"
    static let uploadBucket = "upload_bucket"
    static let uploadRootDir = "upload_root_dir"
    static let selectedWorkflow = "selected_workflow"
}
