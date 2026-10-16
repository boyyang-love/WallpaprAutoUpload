//
//  SettingsView.swift
//  WallpaperAutoUploadTool
//
//  Created by boyyang on 2026/9/22.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var workflowJSON: String = ""
    @State private var showImportSheet = false
    @State private var importText = ""
    @State private var importError: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            // ── 后台 API ──
            Section {
                LabeledContent("地址") {
                    TextField("API 地址", text: $settings.apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Token") {
                    SecureField("未设置", text: $settings.apiToken)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Label("后台 API", systemImage: "server.rack")
            }

            // ── AI 模型 ──
            Section {
                LabeledContent("地址") {
                    TextField("AI API 地址", text: $settings.aiBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Key") {
                    SecureField("未设置", text: $settings.aiAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("模型") {
                    TextField("模型名", text: $settings.aiModel)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("超时") {
                    Picker("", selection: $settings.aiTimeout) {
                        Text("30 秒").tag(30)
                        Text("60 秒").tag(60)
                        Text("120 秒").tag(120)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            } header: {
                Label("AI 模型", systemImage: "brain")
            }

            // ── 上传配置 ──
            Section {
                LabeledContent("质量") {
                    Picker("", selection: $settings.uploadQuality) {
                        ForEach(1...10, id: \.self) { q in
                            Text("\(q)").tag(q)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
                LabeledContent("状态") {
                    Text(settings.uploadStatus == 1 ? "启用" : "禁用")
                        .foregroundStyle(settings.uploadStatus == 1 ? .green : .secondary)
                        .onTapGesture {
                            settings.uploadStatus = settings.uploadStatus == 1 ? 2 : 1
                        }
                        .help("点击切换")
                }
                LabeledContent("目录") {
                    TextField("OSS 目录", text: $settings.uploadDir)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Bucket") {
                    TextField("Bucket 名称", text: $settings.uploadBucket)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("根目录") {
                    TextField("上传根目录", text: $settings.uploadRootDir)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Label("上传配置", systemImage: "arrow.up.circle")
            }

            // ── 工作流配置 ──
            Section {
                // 当前工作流信息
                if let workflow = settings.workflow {
                    LabeledContent("当前工作流") {
                        Text(workflow.name)
                            .foregroundStyle(.primary)
                    }
                    LabeledContent("说明") {
                        Text(workflow.description)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                // 切换内置模板
                LabeledContent("切换模板") {
                    Menu("选择模板") {
                        ForEach(TemplateStore.allTemplates, id: \.name) { template in
                            Button(template.name) {
                                if let config = TemplateStore.loadTemplate(name: template.name) {
                                    settings.setWorkflow(config)
                                    workflowJSON = settings.selectedWorkflow
                                }
                            }
                        }
                    }
                }

                // 编辑 JSON
                VStack(alignment: .leading, spacing: 8) {
                    Text("工作流 JSON")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $workflowJSON)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Button("应用更改") {
                            let (_, error) = TemplateStore.importFromJSON(workflowJSON)
                            if let error {
                                importError = error
                            } else {
                                settings.selectedWorkflow = workflowJSON
                                importError = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("导入 JSON") {
                            showImportSheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        if let error = importError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            } header: {
                Label("工作流配置", systemImage: "gearshape.2")
            } footer: {
                Text("选择内置模板或导入自定义 JSON 配置来定义工作流。详见 README 中的配置格式说明。")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .onAppear {
            // 格式化 JSON 显示
            if let data = settings.selectedWorkflow.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                workflowJSON = String(data: pretty, encoding: .utf8) ?? settings.selectedWorkflow
            } else {
                workflowJSON = settings.selectedWorkflow
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportWorkflowSheet(isPresented: $showImportSheet, settings: settings, workflowJSON: $workflowJSON)
        }
    }
}

// MARK: - 导入工作流 Sheet

struct ImportWorkflowSheet: View {
    @Binding var isPresented: Bool
    let settings: AppSettings
    @Binding var workflowJSON: String
    @State private var importText = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("导入工作流配置")
                .font(.headline)

            Text("粘贴 JSON 配置内容：")
                .foregroundStyle(.secondary)

            TextEditor(text: $importText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 300)
                .border(Color.secondary.opacity(0.3))

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("取消") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("导入") {
                    let (config, err) = TemplateStore.importFromJSON(importText)
                    if let config {
                        settings.setWorkflow(config)
                        workflowJSON = settings.selectedWorkflow
                        isPresented = false
                    } else {
                        error = err
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(importText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppSettings())
}
