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
    @State private var selection: SidebarItem? = .upload

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
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
}
