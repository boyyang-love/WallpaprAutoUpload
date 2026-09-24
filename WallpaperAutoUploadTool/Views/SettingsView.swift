//
//  SettingsView.swift
//  WallpaperAutoUploadTool
//
//  Created by boyyang on 2026/9/22.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

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
            } header: {
                Label("上传配置", systemImage: "arrow.up.circle")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppSettings())
}
