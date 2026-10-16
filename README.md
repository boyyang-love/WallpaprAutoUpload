# 🖼️ WallpaperAutoUploadTool

AI 智能分类 + 批量上传图片的 macOS 原生工具。**配置驱动**，通过 JSON 工作流定义适配不同后端和业务场景。

## ✨ 功能

- **配置驱动** - 通过 JSON 工作流配置适配不同后端，无需改代码
- **批量上传** - 选择文件夹，一键上传所有图片
- **AI 智能分析** - AI 分析图片内容，自动生成名称、标签等元数据
- **灵活实体管理** - 自动匹配或创建标签、分类等关联实体
- **多模板支持** - 内置多种工作流模板，支持导入自定义配置
- **上传历史** - 记录每次上传的详细信息

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

首次启动时会弹出设置引导，也可以稍后在 **设置** 页面手动配置。

### API 配置

| 配置项 | 说明 |
|--------|------|
| API 地址 | 后台服务器地址（如 `https://your-api.example.com`） |
| API Token | 登录后从浏览器开发者工具获取 |

### AI 配置

| 配置项 | 说明 |
|--------|------|
| AI 地址 | OpenAI 兼容的 API 地址（如 `https://api.openai.com/v1`） |
| AI Key | API 密钥 |
| AI 模型 | 使用的模型名称（需支持视觉/图片输入） |
| AI 超时 | 请求超时时间（默认 60 秒） |

### 上传配置

| 配置项 | 说明 |
|--------|------|
| 质量 | 图片质量 1-10（默认 5） |
| 状态 | 上传后状态：启用(1) / 禁用(2) |
| 目录 | OSS 存储目录名 |
| Bucket | OSS Bucket 名称 |
| 根目录 | 上传根目录标识（默认 `IMAGES`） |

### 工作流配置

工具通过 JSON 工作流配置定义完整的上传流程。首次启动默认使用「壁纸上传」模板。

在 **设置 → 工作流配置** 中可以：
- 切换内置模板（壁纸上传 / 简单图片上传 / 基础模板）
- 直接编辑 JSON
- 导入自定义 JSON 配置

#### 工作流 JSON 格式

```json
{
  "name": "工作流名称",
  "description": "描述",
  "version": "1.0",
  "ai": {
    "output_fields": [
      {"name": "字段名", "type": "string|array", "description": "AI 输出描述", "entity": "关联实体名（可选）"}
    ]
  },
  "entities": {
    "实体名": {
      "list_path": "/api/list",
      "create_path": "/api/create",
      "create_body": {"name": "{{name}}", "其他字段": "值"}
    }
  },
  "upload": {
    "path": "/api/upload",
    "fields": {
      "字段名": {"source": "file|ai|entity_ids|setting|value", "...": "..."}
    }
  }
}
```

#### 字段源类型 (source)

| source | 说明 | 额外参数 |
|--------|------|----------|
| `file` | 图片文件数据 | 无 |
| `ai` | AI 分析结果 | `field`: AI 字段名, `separator`: 数组分隔符（可选） |
| `entity_ids` | 实体匹配/创建后的 ID | `field`: 实体名, `separator`: 分隔符（可选） |
| `setting` | AppSettings 通用设置 | `key`: apiBaseURL/aiModel/uploadQuality/uploadDir 等 |
| `value` | 固定值 | `value`: 字符串值 |

#### 内置模板

| 模板 | 说明 |
|------|------|
| 壁纸上传 | 完整流程：AI 分析 + 标签/分类/推荐实体管理 |
| 简单图片上传 | 仅 AI 生成名称和描述，无实体关联 |
| 基础模板 | 最简配置，适合自定义起点 |

## 🔌 后端 API 接口规范

后端接口通过工作流 JSON 配置，以下是「壁纸上传」模板的默认接口规范：

### 通用响应格式

```json
{
  "code": 1,
  "msg": "success",
  "data": { ... }
}
```

`code` 为 1 表示成功，其他值表示失败。

### 实体接口（通用格式）

所有实体（标签/分类/推荐）遵循相同格式：

**列表接口** - `GET /{entity}/info?page=1&limit=10000`
```json
{
  "code": 1,
  "data": {
    "records": [{"id": "1", "name": "名称"}, ...]
  }
}
```

**创建接口** - `POST /{entity}/create`
```json
{"name": "名称", "sort": "0"}
```

### 图片上传接口

`POST /image/upload`（multipart/form-data）

| 字段 | 说明 |
|------|------|
| file | 图片文件 |
| file_name | SEO 文件名 |
| root_dir | 根目录 |
| dir | 子目录 |
| bucket_name | Bucket |
| quality | 质量 1-10 |
| status | 1=启用, 2=禁用 |
| type | PC / MOA |
| tags | 标签 ID（逗号分隔） |
| category | 分类 ID |
| recommend | 推荐标签 ID |

### 认证方式

所有请求通过 HTTP Header `Authorization` 传递 Token。

## 📋 系统要求

- macOS 27.0 或更高版本
- Xcode 27.0（源码编译）

## 📄 许可证

MIT License

## 🔗 相关项目

- [WallpaperMeow](https://github.com/boyyang-love/WallpaperMeow) - macOS 壁纸应用
- [WallpaperCat](https://github.com/boyyang-love/WallpaperCat) - iOS 壁纸应用
- [wallpaper-portal-v2](https://github.com/boyyang-love/wallpaper-portal-v2) - 壁纸网页端
