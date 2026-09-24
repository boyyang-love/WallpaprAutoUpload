//
//  HistoryModels.swift
//  WallpaperAutoUploadTool
//
//  Created by boyyang on 2026/9/22.
//

import Foundation
import SwiftData

/// 一次上传记录
@Model
final class UploadRecord {
    var id: UUID
    var folderPath: String
    var date: Date
    var totalCount: Int
    var successCount: Int
    var failedCount: Int
    @Relationship(deleteRule: .cascade) var items: [UploadRecordItem]

    init(folderPath: String, date: Date, totalCount: Int,
         successCount: Int, failedCount: Int, items: [UploadRecordItem]) {
        self.id = UUID()
        self.folderPath = folderPath
        self.date = date
        self.totalCount = totalCount
        self.successCount = successCount
        self.failedCount = failedCount
        self.items = items
    }
}

/// 单条上传明细
@Model
final class UploadRecordItem {
    var id: UUID
    var fileName: String
    var filePath: String
    var imageType: String   // "MOA" / "PC"
    var status: String      // "success" / "failed" / "dry_run"
    var uploadID: String
    var errorMessage: String
    var category: String
    var tags: String        // 逗号分隔
    var parentRecord: UploadRecord?

    init(fileName: String, filePath: String, imageType: String,
         status: String, uploadID: String = "", errorMessage: String = "",
         category: String = "", tags: String = "") {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.imageType = imageType
        self.status = status
        self.uploadID = uploadID
        self.errorMessage = errorMessage
        self.category = category
        self.tags = tags
    }
}
