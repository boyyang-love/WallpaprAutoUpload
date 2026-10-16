//
//  WorkflowConfig.swift
//  WallpaperAutoUploadTool
//
//  配置驱动的工作流模型 + 内置模板 + 模板管理
//

import Foundation

// MARK: - WorkflowConfig

struct WorkflowConfig {
    let name: String
    let description: String
    let version: String
    let ai: AIConfig
    let entities: [EntityConfig]
    let upload: UploadConfig

    struct AIConfig {
        let outputFields: [OutputField]
    }

    struct OutputField {
        let name: String
        let type: String
        let description: String
        let entityName: String?
    }

    struct EntityConfig {
        let name: String
        let listPath: String
        let createPath: String
        let createBody: [String: String]
    }

    struct UploadConfig {
        let path: String
        let imageType: String?
        let fields: [String: UploadFieldSource]
    }

    struct UploadFieldSource {
        let source: String
        let field: String?
        let key: String?
        let value: String?
        let separator: String?
        let entity: String?
    }

    // MARK: - Init from JSON

    init?(json: [String: Any]) {
        guard let name = json["name"] as? String else { return nil }

        self.name = name
        self.description = json["description"] as? String ?? ""
        self.version = json["version"] as? String ?? "1.0"

        // Parse AI config
        let aiDict = json["ai"] as? [String: Any] ?? [:]
        var fields: [OutputField] = []
        if let outputFields = aiDict["output_fields"] as? [[String: Any]] {
            for f in outputFields {
                guard let fname = f["name"] as? String,
                      let ftype = f["type"] as? String,
                      let fdesc = f["description"] as? String else { continue }
                fields.append(OutputField(
                    name: fname, type: ftype,
                    description: fdesc,
                    entityName: f["entity"] as? String
                ))
            }
        }
        self.ai = AIConfig(outputFields: fields)

        // Parse entities
        var entities: [EntityConfig] = []
        if let entitiesDict = json["entities"] as? [String: Any] {
            for (eName, eValue) in entitiesDict {
                guard let eDict = eValue as? [String: Any],
                      let listPath = eDict["list_path"] as? String,
                      let createPath = eDict["create_path"] as? String else { continue }
                let createBody = eDict["create_body"] as? [String: String] ?? ["name": "{{name}}"]
                entities.append(EntityConfig(
                    name: eName, listPath: listPath,
                    createPath: createPath, createBody: createBody
                ))
            }
        }
        self.entities = entities

        // Parse upload config
        let uploadDict = json["upload"] as? [String: Any] ?? [:]
        let uploadPath = uploadDict["path"] as? String ?? "/upload"
        let uploadImageType = uploadDict["image_type"] as? String

        var fieldSources: [String: UploadFieldSource] = [:]
        if let fieldsDict = uploadDict["fields"] as? [String: Any] {
            for (fName, fValue) in fieldsDict {
                guard let fDict = fValue as? [String: Any],
                      let source = fDict["source"] as? String else { continue }
                fieldSources[fName] = UploadFieldSource(
                    source: source,
                    field: fDict["field"] as? String,
                    key: fDict["key"] as? String,
                    value: fDict["value"] as? String,
                    separator: fDict["separator"] as? String,
                    entity: fDict["entity"] as? String
                )
            }
        }
        self.upload = UploadConfig(
            path: uploadPath,
            imageType: uploadImageType,
            fields: fieldSources
        )
    }

    // MARK: - AI Prompt Generation

    func generateAIPrompt(existingData: String? = nil) -> String {
        var parts = [String]()

        parts.append("分析这张图片，返回 JSON 格式：")

        var jsonFields: [String] = []
        for f in ai.outputFields {
            switch f.type {
            case "array":
                jsonFields.append("  \"\(f.name)\": [\"\(f.description)1\", \"\(f.description)2\"]")
            default:
                jsonFields.append("  \"\(f.name)\": \"\(f.description)\"")
            }
        }
        parts.append("{\n\(jsonFields.joined(separator: ",\n"))\n}")

        parts.append("\n要求：")

        var requirements: [String] = []
        requirements.append("- 所有文本用中文")
        requirements.append("- 只返回 JSON，不要其他内容")

        // Add entity-specific requirements
        for field in ai.outputFields {
            if let entityName = field.entityName {
                if field.type == "array" {
                    requirements.append("- \(field.description) 3-20个，优先从已有\(field.description)中选，没有合适的可自创")
                } else {
                    requirements.append("- \(field.description) 必须从已有\(field.description)中选择，不能自创")
                }
            }
            if field.name.contains("seo") || field.name.contains("name") {
                if field.name.contains("seo") {
                    requirements.append("- \(field.name) 必须是中文，用空格分隔关键词")
                }
            }
        }

        parts.append(requirements.joined(separator: "\n"))

        // Append existing data if available
        if let data = existingData, !data.isEmpty {
            parts.append("\n当前系统已有数据（必须从中选择，不要自创）：")
            parts.append(data)
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - TemplateStore

enum TemplateStore {

    // MARK: - Built-in Templates

    static let wallpaper = WorkflowConfig(json: [
        "name": "壁纸上传",
        "description": "AI 智能分类壁纸上传，自动创建标签、分类和推荐标签",
        "version": "1.0",
        "ai": [
            "output_fields": [
                ["name": "name", "type": "string", "description": "简短的中文图片名称（5-30字）"],
                ["name": "description", "type": "string", "description": "图片内容简述"],
                ["name": "seo_name", "type": "string", "description": "SEO友好的中文文件名（用空格分隔，2-8个关键词）"],
                ["name": "category", "type": "string", "description": "分类", "entity": "category"],
                ["name": "tags", "type": "array", "description": "标签", "entity": "tag"],
                ["name": "recommend", "type": "array", "description": "推荐标签", "entity": "recommend"],
            ]
        ],
        "entities": [
            "tag": [
                "list_path": "/tag/info",
                "create_path": "/tag/create",
                "create_body": ["name": "{{name}}", "type": "wallpaper", "sort": "0"],
            ],
            "category": [
                "list_path": "/category/info",
                "create_path": "/category/create",
                "create_body": ["name": "{{name}}", "cover_id": "", "cover": "", "sort": "0", "web": "true", "moa": "true"],
            ],
            "recommend": [
                "list_path": "/recommend/info",
                "create_path": "/recommend/create",
                "create_body": ["name": "{{name}}", "sort": "0"],
            ],
        ],
        "upload": [
            "path": "/image/upload",
            "fields": [
                "file": ["source": "file"],
                "file_name": ["source": "ai", "field": "seo_name"],
                "root_dir": ["source": "setting", "key": "uploadRootDir"],
                "dir": ["source": "setting", "key": "uploadDir"],
                "bucket_name": ["source": "setting", "key": "uploadBucket"],
                "quality": ["source": "setting", "key": "uploadQuality"],
                "status": ["source": "setting", "key": "uploadStatus"],
                "type": ["source": "setting", "key": "imageType"],
                "tags": ["source": "entity_ids", "field": "tags", "entity": "tag", "separator": ","],
                "category": ["source": "entity_ids", "field": "category", "entity": "category", "separator": ","],
                "recommend": ["source": "entity_ids", "field": "recommend", "entity": "recommend", "separator": ","],
                "group": ["source": "value", "value": ""],
                "album": ["source": "value", "value": ""],
            ],
        ],
    ] as [String: Any])

    static let simpleUpload = WorkflowConfig(json: [
        "name": "简单图片上传",
        "description": "仅上传图片，AI 生成名称和描述，无需标签/分类等实体",
        "version": "1.0",
        "ai": [
            "output_fields": [
                ["name": "name", "type": "string", "description": "简短的中文图片名称（5-30字）"],
                ["name": "description", "type": "string", "description": "图片内容简述"],
                ["name": "seo_name", "type": "string", "description": "SEO友好的中文文件名（用空格分隔，2-8个关键词）"],
            ]
        ],
        "entities": [:],
        "upload": [
            "path": "/upload",
            "fields": [
                "file": ["source": "file"],
                "file_name": ["source": "ai", "field": "seo_name"],
                "name": ["source": "ai", "field": "name"],
                "description": ["source": "ai", "field": "description"],
            ],
        ],
    ] as [String: Any])

    static let basic: WorkflowConfig? = WorkflowConfig(json: [
        "name": "基础模板",
        "description": "最简单的配置模板，适合作为自定义工作流的起点",
        "version": "1.0",
        "ai": [
            "output_fields": [
                ["name": "name", "type": "string", "description": "图片名称"],
                ["name": "tags", "type": "array", "description": "标签", "entity": "tag"],
            ]
        ],
        "entities": [
            "tag": [
                "list_path": "/tag/list",
                "create_path": "/tag/add",
                "create_body": ["name": "{{name}}"],
            ],
        ],
        "upload": [
            "path": "/upload",
            "fields": [
                "file": ["source": "file"],
                "name": ["source": "ai", "field": "name"],
                "tags": ["source": "entity_ids", "field": "tags", "entity": "tag", "separator": ","],
            ],
        ],
    ])

    // MARK: - Built-in Templates Dictionary

    private static let builtInTemplates: [String: WorkflowConfig] = {
        var dict: [String: WorkflowConfig] = [:]
        if let t = wallpaper { dict[t.name] = t }
        if let t = simpleUpload { dict[t.name] = t }
        if let t = basic { dict[t.name] = t }
        return dict
    }()

    /// 所有可用模板列表
    static var allTemplates: [(name: String, description: String)] {
        var list: [(name: String, description: String)] = []
        for (_, config) in builtInTemplates.sorted(by: { $0.key < $1.key }) {
            list.append((name: config.name, description: config.description))
        }
        return list
    }

    /// 按名称加载内置模板
    static func loadTemplate(name: String) -> WorkflowConfig? {
        builtInTemplates[name]
    }

    /// 从 JSON 字符串导入自定义配置
    static func importFromJSON(_ jsonString: String) -> (config: WorkflowConfig?, error: String?) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, "JSON 解析失败，请检查格式")
        }
        guard let config = WorkflowConfig(json: json) else {
            return (nil, "配置格式不正确，缺少必要字段（name）")
        }
        return (config, nil)
    }
}