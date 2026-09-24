# 🖼️ WallpaperAutoUploadTool

AI 智能分类 + 批量上传壁纸到后台的 macOS 原生工具。

## ✨ 功能

- **批量上传** - 选择文件夹，一键上传所有壁纸
- **AI 智能分类** - 自动识别壁纸类型（手机/电脑）
- **智能打标签** - AI 分析图片内容，自动生成标签
- **上传历史** - 记录每次上传的详细信息
- **配置灵活** - 支持自定义 API、AI 模型等设置

## 📦 安装

### 方式一：下载 DMG（推荐）

1. 前往 [Releases](https://github.com/boyyang-love/WallpaprAutoUpload/releases) 页面
2. 下载最新版本的 `WallpaperAutoUploadTool.dmg`
3. 打开 DMG，将应用拖到 Applications 文件夹
4. 首次启动需要在 **系统设置 → 隐私与安全性** 中允许运行

### 方式二：源码编译

```bash
git clone git@github.com:boyyang-love/WallpaprAutoUpload.git
cd WallpaperAutoUploadTool
open WallpaperAutoUploadTool.xcodeproj
```

在 Xcode 中编译运行（需要 macOS 27.0+）

## 🚀 使用方法

1. 打开应用，进入 **设置** 页面配置：
   - 后台 API 地址和 Token
   - AI API 地址和 Key
   - 上传参数（质量、状态等）

2. 进入 **上传任务** 页面：
   - 点击选择包含壁纸的文件夹
   - 点击 **开始上传**
   - AI 会自动分析每张图片并生成标签
   - 上传完成后查看结果

3. 进入 **历史记录** 页面查看上传记录

## 📁 项目结构

```
WallpaperAutoUploadTool/
├── Models/
│   ├── AppSettings.swift      # 设置模型
│   └── HistoryModels.swift    # 历史记录模型
├── Services/
│   ├── API.swift              # 网络请求
│   └── UploadViewModel.swift  # 上传逻辑
├── Views/
│   ├── UploadView.swift       # 上传页面
│   ├── SettingsView.swift     # 设置页面
│   └── HistoryView.swift      # 历史记录页面
├── ContentView.swift          # 主界面
└── WallpaperAutoUploadToolApp.swift  # App 入口
```

## 🔧 配置说明

### API 配置

| 配置项 | 说明 |
|--------|------|
| API 地址 | 后台服务器地址 |
| API Token | 登录后从浏览器开发者工具获取 |

### AI 配置

| 配置项 | 说明 |
|--------|------|
| AI 地址 | OpenAI 兼容的 API 地址 |
| AI Key | API 密钥 |
| AI 模型 | 使用的模型名称 |

## 📋 系统要求

- macOS 27.0 或更高版本
- Xcode 27.0（源码编译）

## 📄 许可证

MIT License

## 🔗 相关项目

- [WallpaperMeow](https://github.com/boyyang-love/WallpaperMeow) - macOS 壁纸应用
- [WallpaperCat](https://github.com/boyyang-love/WallpaperCat) - iOS 壁纸应用
- [wallpaper-portal-v2](https://github.com/boyyang-love/wallpaper-portal-v2) - 壁纸网页端
