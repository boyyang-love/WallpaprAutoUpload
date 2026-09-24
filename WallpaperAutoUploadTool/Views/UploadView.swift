//
//  UploadView.swift
//  WallpaperAutoUploadTool
//
//  Created by boyyang on 2026/9/22.
//

import SwiftUI
import SwiftData

struct UploadView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var vm = UploadViewModel()

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                folderSection
                if vm.hasImages {
                    imageGrid
                    actionBar
                    resultsSummary
                }
            }
            .padding()
        }
        .navigationTitle("上传任务")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first,
                  url.hasDirectoryPath else { return false }
            vm.selectedFolder = url.path
            // 直接调用加载，这里需要重新实现
            return true
        }
    }

    // MARK: - 选择文件夹

    private var folderSection: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)

            if vm.selectedFolder.isEmpty {
                Text("拖拽文件夹到此处，或点击选择")
                    .foregroundStyle(.secondary)
            } else {
                Text(vm.selectedFolder)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("选择文件夹") {
                vm.selectFolder()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 图片网格

    private var imageGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(vm.images) { item in
                ImageCard(item: item, isSelected: vm.selectedIDs.contains(item.id))
                    .onTapGesture { vm.toggleSelection(item.id) }
                    .contextMenu {
                        if item.status.canReAnalyze {
                            Button("重新分析") {
                                Task { await vm.reAnalyzeImage(id: item.id, settings: settings) }
                            }
                        }
                        if item.status.canReUpload {
                            Divider()
                            Button("重新上传") {
                                Task { await vm.reUploadImage(id: item.id, settings: settings) }
                            }
                        }
                    }
            }
        }
        .id(vm.refreshID)
    }

    // MARK: - 操作栏

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(vm.isAllSelected ? "取消全选" : "全选") {
                vm.toggleSelectAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Text("已选 \(vm.selectedCount) 张")
                .foregroundStyle(.secondary)

            Spacer()

            if vm.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
                Text("分析中...")
                    .foregroundStyle(.secondary)
            }

            Button("开始分析") {
                Task { await vm.analyzeImages(settings: settings) }
            }
            .buttonStyle(.bordered)
            .disabled(vm.selectedIDs.isEmpty || vm.isAnalyzing)

            Button("全部上传") {
                Task { await vm.uploadImages(settings: settings, modelContext: modelContext) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isUploading || vm.analyzedCount == 0)

            Button("试运行") {
                Task { await vm.uploadImages(settings: settings, dryRun: true, modelContext: modelContext) }
            }
            .buttonStyle(.bordered)
            .disabled(vm.isUploading || vm.analyzedCount == 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 结果汇总

    @ViewBuilder
    private var resultsSummary: some View {
        let successTotal = vm.successCount
        let failTotal = vm.failedCount
        let analyzedTotal = vm.analyzedCount

        if successTotal + failTotal + analyzedTotal > 0 {
            HStack(spacing: 16) {
                if successTotal > 0 {
                    Label("已上传 \(successTotal)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if analyzedTotal > 0 {
                    Label("待上传 \(analyzedTotal)", systemImage: "arrow.up.circle")
                        .foregroundStyle(.blue)
                }
                if failTotal > 0 {
                    Label("失败 \(failTotal)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(.callout)
            .padding(.vertical, 4)
        }

        if let error = vm.errorMessage {
            Text(error)
                .font(.callout)
                .foregroundStyle(.red)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - 图片卡片

private struct ImageCard: View {
    let item: ImageItem
    let isSelected: Bool

    private var hasAnalysis: Bool { item.analysis != nil }

    private let tagColumns = [GridItem(.adaptive(minimum: 40), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ── 图片 + 角标 ──
            ZStack(alignment: .topTrailing) {
                if let thumb = item.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                        .frame(height: 120)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }

                Text(item.isPortrait ? "MOA" : "PC")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                statusBadge
                    .padding(4)
            }
            .overlay(alignment: .bottom) {
                if case .uploading = item.status, item.uploadProgress > 0 {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * item.uploadProgress, height: 3)
                    }
                    .frame(height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // ── 文件名 ──
            Text(item.fileName)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)

            // ── 分析结果 ──
            if let analysis = item.analysis {
                analysisSection(analysis)
            }

            // ── 失败原因 ──
            if let error = item.status.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }

    // MARK: - 分析结果

    @ViewBuilder
    private func analysisSection(_ analysis: ImageAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()

            // 名称
            if !analysis.name.isEmpty {
                Text(analysis.name)
                    .font(.caption)
                    .lineLimit(1)
            }

            // 分类
            if !analysis.category.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(analysis.category)
                        .font(.caption2)
                }
            }

            // 标签
            if !analysis.tags.isEmpty {
                LazyVGrid(columns: tagColumns, alignment: .leading, spacing: 3) {
                    ForEach(analysis.tags.prefix(8), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            // SEO 名
            if !analysis.seoName.isEmpty {
                Text(analysis.seoName)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 状态徽标

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .pending:
            EmptyView()
        case .analyzing:
            ProgressView()
                .controlSize(.mini)
                .padding(3)
        case .analyzed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .uploading:
            if item.uploadProgress > 0 {
                Text("\(Int(item.uploadProgress * 100))%")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 3))
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .padding(3)
            }
        case .success:
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }
}

#Preview {
    UploadView()
        .environment(AppSettings())
}
