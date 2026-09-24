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

    // MARK: - 上传配置

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

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard

        // 注册默认值
        defaults.register(defaults: [
            Keys.apiBaseURL: Defaults.apiBaseURL,
            Keys.apiToken: "",
            Keys.aiBaseURL: Defaults.aiBaseURL,
            Keys.aiAPIKey: "",
            Keys.aiModel: Defaults.aiModel,
            Keys.aiTimeout: Defaults.aiTimeout,
            Keys.uploadQuality: Defaults.uploadQuality,
            Keys.uploadStatus: Defaults.uploadStatus,
            Keys.uploadDir: Defaults.uploadDir,
            Keys.uploadBucket: Defaults.uploadBucket,
        ])

        self.apiBaseURL = defaults.string(forKey: Keys.apiBaseURL) ?? Defaults.apiBaseURL
        self.apiToken = defaults.string(forKey: Keys.apiToken) ?? ""
        self.aiBaseURL = defaults.string(forKey: Keys.aiBaseURL) ?? Defaults.aiBaseURL
        self.aiAPIKey = defaults.string(forKey: Keys.aiAPIKey) ?? ""
        self.aiModel = defaults.string(forKey: Keys.aiModel) ?? Defaults.aiModel
        self.aiTimeout = defaults.integer(forKey: Keys.aiTimeout)
        self.uploadQuality = defaults.integer(forKey: Keys.uploadQuality)
        self.uploadStatus = defaults.integer(forKey: Keys.uploadStatus)
        self.uploadDir = defaults.string(forKey: Keys.uploadDir) ?? Defaults.uploadDir
        self.uploadBucket = defaults.string(forKey: Keys.uploadBucket) ?? Defaults.uploadBucket
    }
}

// MARK: - Keys & Defaults

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
}

enum Defaults {
    static let apiBaseURL = "https://wallpaper.boyyang.cn"
    static let aiBaseURL = "https://token-plan-cn.xiaomimimo.com/v1"
    static let aiModel = "mimo-v2.5"
    static let aiTimeout = 60
    static let uploadQuality = 5
    static let uploadStatus = 1
    static let uploadDir = "PCANDMOA"
    static let uploadBucket = "wallpaper"
}
