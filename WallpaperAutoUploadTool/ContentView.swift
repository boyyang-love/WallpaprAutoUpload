//
//  ContentView.swift
//  WallpaperAutoUploadTool
//
//  Created by boyyang on 2026/9/22.
//

import SwiftUI

/// 侧栏导航项
private enum SidebarItem: String, CaseIterable, Identifiable {
    case upload = "上传任务"
    case settings = "设置"
    case history = "历史记录"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .upload: return "arrow.up.circle"
        case .settings: return "gearshape"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @State private var selection: SidebarItem? = .upload
    @State private var showSetupGuide = false

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selection {
            case .upload:
                UploadView()
            case .settings:
                SettingsView()
            case .history:
                HistoryView()
            case .none:
                Text("请选择功能")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            if !settings.isConfigured {
                showSetupGuide = true
            }
        }
        .sheet(isPresented: $showSetupGuide) {
            SetupGuideView(isPresented: $showSetupGuide)
        }
    }
}

// MARK: - 首次启动设置引导

struct SetupGuideView: View {
    @Environment(AppSettings.self) private var settings
    @Binding var isPresented: Bool

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 20) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("欢迎使用 WallpaperAutoUploadTool")
                .font(.title2)
                .fontWeight(.semibold)

            Text("首次使用请先配置以下信息")
                .foregroundStyle(.secondary)

            Form {
                Section("后台 API") {
                    LabeledContent("地址") {
                        TextField("https://your-api.example.com", text: $settings.apiBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Token") {
                        SecureField("从后台获取的 Token", text: $settings.apiToken)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("AI 模型（可选，后续在设置中配置）") {
                    LabeledContent("地址") {
                        TextField("OpenAI 兼容 API 地址", text: $settings.aiBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Key") {
                        SecureField("API Key", text: $settings.aiAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("模型") {
                        TextField("模型名称", text: $settings.aiModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("工作流模板") {
                    ForEach(TemplateStore.allTemplates, id: \.name) { template in
                        let isSelected = settings.workflow?.name == template.name
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .fontWeight(isSelected ? .semibold : .regular)
                                Text(template.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let config = TemplateStore.loadTemplate(name: template.name) {
                                settings.setWorkflow(config)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 500)

            HStack {
                Button("稍后设置") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("开始使用") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.apiBaseURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(30)
        .frame(width: 500)
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
}
