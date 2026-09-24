//
//  HistoryView.swift
//  WallpaperAutoUploadTool
//
//  Created by boyyang on 2026/9/22.
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \UploadRecord.date, order: .reverse) private var records: [UploadRecord]
    @State private var selectedRecord: UploadRecord?
    @State private var expandedIDs: Set<UUID> = []

    var body: some View {
        Group {
            if records.isEmpty {
                emptyState
            } else {
                recordList
            }
        }
        .navigationTitle("历史记录")
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("暂无上传记录")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("完成一次上传后，记录会自动出现在这里")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 记录列表

    private var recordList: some View {
        List(records, selection: $selectedRecord) { record in
            DisclosureGroup(isExpanded: disclosureBinding(for: record)) {
                recordDetail(record)
            } label: {
                recordRow(record)
            }
            .tag(record)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - 单行

    private func recordRow(_ record: UploadRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.folderPath)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(record.date, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                if record.successCount > 0 {
                    Label("\(record.successCount)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                if record.failedCount > 0 {
                    Label("\(record.failedCount)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                Text("\(record.totalCount) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 展开详情

    private func recordDetail(_ record: UploadRecord) -> some View {
        VStack(spacing: 0) {
            ForEach(record.items) { item in
                HStack(spacing: 10) {
                    // 状态图标
                    statusIcon(for: item.status)

                    // 文件名
                    Text(item.fileName)
                        .font(.callout)
                        .lineLimit(1)

                    // 类型
                    Text(item.imageType)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))

                    Spacer()

                    // 分类
                    if !item.category.isEmpty {
                        Text(item.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 上传 ID 或错误信息
                    if item.status == "success" && !item.uploadID.isEmpty {
                        Text("ID: \(item.uploadID)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if item.status == "failed" && !item.errorMessage.isEmpty {
                        Text(item.errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)

                if item.id != record.items.last?.id {
                    Divider()
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusIcon(for status: String) -> some View {
        switch status {
        case "success":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case "dry_run":
            Image(systemName: "eye.circle.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        default:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Helpers

    private func disclosureBinding(for record: UploadRecord) -> Binding<Bool> {
        Binding(
            get: { expandedIDs.contains(record.id) },
            set: { if $0 { expandedIDs.insert(record.id) } else { expandedIDs.remove(record.id) } }
        )
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
    .modelContainer(for: [UploadRecord.self, UploadRecordItem.self], inMemory: true)
}
