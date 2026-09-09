# ClipDock Windows 平台开发指南

> 本文档用于指导 ClipDock Windows Edition 的架构设计、开发环境搭建、核心技术选型、测试流程和发布策略。

---

# 1. 项目目标

ClipDock 当前主要运行在 macOS 平台，Windows Edition 的目标不是简单移植 UI，而是在 Windows 平台实现与 macOS 版本尽可能一致的核心功能和用户体验。

总体原则：

> **平台原生实现 + 功能行为一致**

最终架构：

```text
                    ClipDock
                        │
        ┌───────────────┴───────────────┐
        │                               │
      macOS                          Windows
        │                               │
 Swift + SwiftUI                 C# + WinUI 3
        │                               │
   NSPasteboard                  Win32 Clipboard
        │                               │
      CoreData                       SQLite
```

两个平台：

- UI 可以不同
- 系统 API 不同
- 数据库实现可以不同
- 但核心功能行为应该保持一致

---

# 2. Windows 技术选型

## 推荐技术栈

| 功能 | 技术 |
|---|---|
| 编程语言 | C# |
| Runtime | .NET 10 |
| UI | WinUI 3 |
| 平台 SDK | Windows App SDK |
| 架构 | MVVM |
| 数据库 | SQLite |
| ORM | EF Core |
| Clipboard | Win32 API |
| 全局快捷键 | RegisterHotKey |
| 系统托盘 | Win32 / Windows App SDK |
| DI | Microsoft.Extensions.DependencyInjection |
| 日志 | Serilog |
| 测试 | xUnit |
| CI | GitHub Actions |

---

# 3. 为什么选择 WinUI 3

ClipDock 是一个系统级桌面工具，需要大量 Windows 系统集成能力：

```text
Clipboard Monitoring
Global Hotkey
System Tray
Window Management
Startup
Background Operation
Native Window Behavior
```

因此 Windows 版本采用：

```text
C#
+
WinUI 3
+
Windows App SDK
+
Win32 API
```

而不是直接使用跨平台 UI 框架。

核心原则：

> UI 使用现代 Windows 技术，系统能力直接使用 Win32 API。

---

# 4. 开发环境

当前开发机器：

```text
Intel Mac
```

推荐开发环境：

```text
Intel Mac
    │
    ├── macOS
    │     ├── Git
    │     ├── VS Code / Rider
    │     └── ClipDock Source
    │
    └── Windows 11 x64
           ├── Visual Studio
           ├── .NET SDK
           └── ClipDock.Windows
```

---

# 5. Windows 测试环境

推荐使用：

## 日常开发

```text
Parallels Desktop
+
Windows 11 x64
```

## 最终系统测试

```text
Boot Camp
+
Windows
```

Parallels 用于：

- 日常运行
- UI 调试
- Clipboard 测试
- SQLite 测试
- Hotkey 测试

Boot Camp 用于：

- 最终性能测试
- 原生系统行为测试
- 全局快捷键测试
- Tray 测试
- 多显示器测试

---

# 6. 虚拟机测试注意事项

ClipDock 是 Clipboard 工具。

虚拟机默认可能启用：

```text
macOS Clipboard
        ↕
Windows Clipboard
```

测试时建议关闭 Clipboard Sharing。

否则可能出现：

```text
macOS Copy
    ↓
Virtual Machine Sync
    ↓
Windows Clipboard
    ↓
ClipDock Capture
```

导致测试结果受到干扰。

---

# 7. 仓库结构

建议仓库逐步调整为：

```text
ClipDock/
│
├── code/
│   └── ClickDock/
│       └── macOS Source
│
├── windows/
│   │
│   ├── ClipDock.sln
│   │
│   ├── src/
│   │   │
│   │   ├── ClipDock.App/
│   │   │
│   │   ├── ClipDock.Core/
│   │   │
│   │   ├── ClipDock.Platform.Windows/
│   │   │
│   │   └── ClipDock.Infrastructure/
│   │
│   └── tests/
│       └── ClipDock.Tests/
│
├── specs/
│
├── docs/
│
└── README.md
```

---

# 8. Windows 项目职责

## ClipDock.App

负责：

```text
WinUI Application
Views
ViewModels
App Startup
Dependency Injection
Window Management
```

目录：

```text
ClipDock.App/
├── App.xaml
├── App.xaml.cs
│
├── Views/
│   ├── MainWindow.xaml
│   ├── ClipboardWindow.xaml
│   └── SettingsWindow.xaml
│
├── ViewModels/
│   ├── ClipboardViewModel.cs
│   ├── SearchViewModel.cs
│   └── SettingsViewModel.cs
│
└── Controls/
```

---

## ClipDock.Core

负责纯业务逻辑。

不依赖：

```text
WinUI
Win32
SQLite
Windows API
```

目录：

```text
ClipDock.Core/
├── Models/
├── Interfaces/
├── Services/
├── Rules/
├── Policies/
└── Utilities/
```

核心逻辑包括：

```text
Clipboard Classification
Deduplication
Content Hash
Sensitive Rules
Search
Categories
```

---

## ClipDock.Platform.Windows

负责 Windows 系统集成。

目录：

```text
ClipDock.Platform.Windows/
├── Clipboard/
├── Hotkey/
├── Tray/
├── Windowing/
├── Startup/
└── Native/
```

---

## ClipDock.Infrastructure

负责基础设施。

```text
ClipDock.Infrastructure/
├── Database/
├── Files/
├── Logging/
├── Settings/
└── Network/
```

---

# 9. Clipboard 架构

ClipDock Windows 的核心架构：

```text
Windows Clipboard
        │
        ▼
WM_CLIPBOARDUPDATE
        │
        ▼
WindowsClipboardMonitor
        │
        ▼
ClipboardCaptureCoordinator
        │
        ├── Retry Policy
        │
        ├── Snapshot Capture
        │
        ▼
ClipboardClassifier
        │
        ▼
SensitiveContentFilter
        │
        ▼
ClipboardDeduplicator
        │
        ▼
ClipboardRepository
        │
        ▼
SQLite
```

---

# 10. Clipboard Monitor

Windows 使用：

```text
AddClipboardFormatListener
```

监听：

```text
WM_CLIPBOARDUPDATE
```

接口：

```csharp
public interface IClipboardMonitor
{
    event EventHandler ClipboardChanged;

    void Start();

    void Stop();
}
```

实现：

```text
WindowsClipboardMonitor
```

职责：

```text
Create Window Handle
        ↓
AddClipboardFormatListener
        ↓
Receive WM_CLIPBOARDUPDATE
        ↓
Raise ClipboardChanged Event
```

---

# 11. 不要直接在 Window Message 中读取 Clipboard

错误方式：

```text
WM_CLIPBOARDUPDATE
        ↓
WndProc
        ↓
直接读取 Clipboard
```

推荐：

```text
WM_CLIPBOARDUPDATE
        ↓
Event
        ↓
Queue
        ↓
Background Capture
```

原因：

Clipboard 可能暂时被其他程序占用。

---

# 12. Clipboard Retry Policy

Windows Clipboard 经常可能出现：

```text
Clipboard Busy
Clipboard Locked
Access Denied
```

因此需要 Retry。

推荐：

```text
Attempt 1 → Immediately

Attempt 2 → 20ms

Attempt 3 → 50ms

Attempt 4 → 100ms

Attempt 5 → 200ms
```

接口：

```csharp
public interface IClipboardRetryPolicy
{
    Task<T?> ExecuteAsync<T>(
        Func<T> action,
        CancellationToken cancellationToken);
}
```

---

# 13. Clipboard Snapshot

不要让后续业务逻辑直接访问 Windows Clipboard。

应该先创建稳定 Snapshot。

```csharp
public sealed record ClipboardSnapshot(
    ClipboardPayloadType PayloadType,
    string? Text,
    byte[]? ImageData,
    IReadOnlyList<string>? FilePaths,
    string? Html
);
```

流程：

```text
Windows Clipboard
        ↓
Read
        ↓
ClipboardSnapshot
        ↓
Business Logic
```

这样 Core 模块完全不依赖 Windows API。

---

# 14. Clipboard 内容类型

建议分成两个维度。

## Payload Type

表示真实数据格式：

```csharp
public enum ClipboardPayloadType
{
    Text,
    Image,
    File,
    Html
}
```

---

## Semantic Type

表示内容语义：

```csharp
public enum ClipboardSemanticType
{
    PlainText,
    Link,
    Code,
    Color,
    Unknown
}
```

例如：

```text
"https://github.com"
```

可以表示为：

```text
PayloadType:

Text

SemanticType:

Link
```

这样比把所有类型塞进一个 Enum 更容易维护。

---

# 15. Clipboard Item

统一业务模型：

```csharp
public sealed class ClipboardItem
{
    public Guid Id { get; set; }

    public ClipboardPayloadType PayloadType { get; set; }

    public ClipboardSemanticType SemanticType { get; set; }

    public string ContentHash { get; set; } = string.Empty;

    public string? TextContent { get; set; }

    public string? AssetPath { get; set; }

    public string? SourceApplication { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset LastUsedAt { get; set; }

    public int UsageCount { get; set; }

    public bool IsPinned { get; set; }
}
```

---

# 16. Content Hash

所有内容统一使用：

```text
SHA256
```

文本：

```text
UTF8
↓
SHA256
```

图片：

```text
Binary Data
↓
SHA256
```

文件：

建议根据：

```text
File Content
```

或：

```text
Normalized File List
```

生成 Hash。

不要把原始文本直接当作：

```text
contentHash
```

---

# 17. Deduplication

统一规则：

```text
Same PayloadType
+
Same ContentHash
=
Duplicate
```

例如：

```text
Copy "Hello"

Copy "Hello"

Copy "Hello"
```

数据库只保存：

```text
Hello
```

但是更新：

```text
UsageCount += 1

LastUsedAt = Now
```

Pinned 状态必须保留。

---

# 18. 文件 Clipboard

Windows 文件通常使用：

```text
CF_HDROP
```

读取到：

```text
C:\Users\User\Desktop\file.pdf
```

不能只保存路径。

正确流程：

```text
Clipboard File
        ↓
Create Clipboard Record
        ↓
Background File Copy
        ↓
ClipDock Asset Storage
        ↓
Update Record
```

---

# 19. Asset Storage

推荐路径：

```text
%LOCALAPPDATA%\ClipDock\
```

结构：

```text
ClipDock/
├── Data/
│   └── clipdock.db
│
├── Assets/
│   ├── Images/
│   └── Files/
│
├── Thumbnails/
│
└── Logs/
```

---

# 20. SQLite 数据库

数据库：

```text
%LOCALAPPDATA%\ClipDock\Data\clipdock.db
```

主要表：

```text
clipboard_items

categories

clipboard_item_categories

settings
```

---

## clipboard_items

```sql
CREATE TABLE clipboard_items (
    id TEXT PRIMARY KEY,

    payload_type INTEGER NOT NULL,

    semantic_type INTEGER NOT NULL,

    content_hash TEXT NOT NULL,

    text_content TEXT,

    asset_path TEXT,

    source_application TEXT,

    created_at INTEGER NOT NULL,

    last_used_at INTEGER NOT NULL,

    usage_count INTEGER NOT NULL DEFAULT 1,

    is_pinned INTEGER NOT NULL DEFAULT 0
);
```

---

# 21. 数据库索引

必须建立：

```sql
CREATE INDEX idx_clipboard_hash
ON clipboard_items(content_hash);

CREATE INDEX idx_clipboard_last_used
ON clipboard_items(last_used_at DESC);

CREATE INDEX idx_clipboard_pinned
ON clipboard_items(is_pinned);
```

---

# 22. Global Hotkey

使用：

```text
RegisterHotKey
```

默认快捷键建议：

```text
Alt + Space
```

或：

```text
Ctrl + Shift + V
```

必须支持用户自定义。

接口：

```csharp
public interface IGlobalHotkeyService
{
    void Register(
        Hotkey hotkey,
        Action callback);

    void UnregisterAll();
}
```

---

# 23. Window 行为

ClipDock 应该作为 Background Utility 运行。

启动后：

```text
Windows Startup
        ↓
ClipDock Background
        ↓
System Tray
```

用户：

```text
Global Hotkey
        ↓
Show Clipboard Window
```

窗口失去焦点：

```text
Lost Focus
        ↓
Hide Window
```

行为类似：

```text
Raycast
Spotlight
PowerToys Run
```

---

# 24. System Tray

Tray 菜单：

```text
Open ClipDock

────────────

Settings

────────────

Quit
```

Tray Icon 应该支持：

```text
Single Click

Double Click

Right Click Menu
```

---

# 25. MVVM 架构

推荐：

```text
View
    │
    ▼
ViewModel
    │
    ▼
Service
    │
    ▼
Repository
    │
    ▼
SQLite
```

禁止：

```text
View
 ↓
直接操作 SQLite
```

也避免：

```text
ViewModel
 ↓
直接调用 Win32 API
```

---

# 26. UI 页面

Windows MVP：

```text
ClipboardWindow
│
├── Search Bar
│
├── Sidebar
│   ├── All
│   ├── Pinned
│   ├── Text
│   ├── Images
│   └── Files
│
├── Clipboard List
│
└── Preview
```

---

# 27. MVP 开发计划

## Phase 1：项目初始化

完成：

```text
✓ WinUI 3
✓ .NET
✓ Dependency Injection
✓ Logging
✓ SQLite
✓ Settings
```

---

## Phase 2：Clipboard MVP

完成：

```text
✓ WM_CLIPBOARDUPDATE

✓ Text Capture

✓ Clipboard History

✓ SQLite

✓ Search

✓ Copy Back

✓ Deduplication
```

完成后应该得到一个真正可用的最小版本。

---

## Phase 3：Windows 系统集成

```text
✓ Global Hotkey

✓ System Tray

✓ Startup

✓ Window Show / Hide
```

---

## Phase 4：更多 Clipboard 类型

```text
✓ Image

✓ Files

✓ HTML

✓ URL

✓ Code

✓ Colors
```

---

## Phase 5：高级功能

```text
✓ Categories

✓ Sensitive Rules

✓ Regex Rules

✓ File Cache

✓ Auto Cleanup

✓ Link Metadata
```

---

# 28. Windows 与 macOS 功能一致性

建议建立：

```text
/specs
```

定义跨平台行为。

例如：

```text
specs/
├── clipboard-item.md
├── deduplication.md
├── sensitive-rules.md
├── search.md
├── categories.md
└── hotkey.md
```

---

## 示例：Deduplication Spec

```text
If:

PayloadType is equal

AND

ContentHash is equal

Then:

Treat as Duplicate

Update:

LastUsedAt

UsageCount

Preserve:

Pinned State

Categories
```

这样：

```text
macOS Implementation
```

和：

```text
Windows Implementation
```

即使代码完全不同，行为仍然一致。

---

# 29. 测试策略

## Unit Tests

测试：

```text
ClipboardClassifier

Deduplicator

Hash

Sensitive Rules

Search

Categories
```

这些测试应该不依赖 Windows。

---

## Integration Tests

测试：

```text
SQLite

Repository

Asset Storage

Clipboard Pipeline
```

---

## Manual Tests

必须在真实 Windows 环境测试：

```text
Clipboard Monitoring

Clipboard Lock

Global Hotkey

System Tray

Window Focus

Multiple Monitors

Startup
```

---

# 30. GitHub Actions

建议：

```text
Push
  ↓
Windows Runner
  ↓
Restore
  ↓
Build
  ↓
Unit Tests
```

基础 CI：

```yaml
name: Windows Build

on:
  push:
    branches:
      - develop

  pull_request:
    branches:
      - develop

jobs:
  build:

    runs-on: windows-latest

    steps:

      - uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4

      - name: Restore
        run: dotnet restore windows/ClipDock.sln

      - name: Build
        run: >
          dotnet build
          windows/ClipDock.sln
          --configuration Release
          --no-restore

      - name: Test
        run: >
          dotnet test
          windows/ClipDock.sln
          --configuration Release
          --no-build
```

---

# 31. Release Architecture

第一阶段发布：

```text
win-x64
```

因为主要测试环境是：

```text
Intel Windows
```

未来支持：

```text
win-x64

win-arm64
```

发布：

```text
dotnet publish
```

例如：

```text
ClipDock.Windows

Release
├── win-x64
└── win-arm64
```

---

# 32. 开发原则

Windows 版本必须遵守以下原则。

## 1. Core 不依赖 UI

```text
Core
```

不能依赖：

```text
WinUI
Windows API
SQLite
```

---

## 2. Clipboard 先 Snapshot

不要让业务逻辑直接访问 Clipboard。

必须：

```text
Clipboard
↓
Snapshot
↓
Business Logic
```

---

## 3. 所有 Clipboard 访问都有 Retry

Windows Clipboard 不是永远可读。

必须考虑：

```text
Clipboard Busy

Clipboard Locked

Access Denied
```

---

## 4. 文件必须异步缓存

不要：

```text
Clipboard Event
↓
Copy 2GB File
↓
UI Freeze
```

应该：

```text
Capture
↓
Persist Record
↓
Background Asset Copy
```

---

## 5. 限制后台任务数量

禁止：

```text
5000 Clipboard Items
↓
5000 Tasks
```

应该：

```text
Queue
↓
Limited Workers
```

---

# 33. 推荐的最终架构

```text
┌──────────────────────────────┐
│          WinUI 3 UI          │
│                              │
│ Views / ViewModels           │
└──────────────┬───────────────┘
               │
┌──────────────▼───────────────┐
│         Application          │
│                              │
│ Clipboard Coordinator        │
│ Search Service               │
│ Settings Service             │
└──────────────┬───────────────┘
               │
┌──────────────▼───────────────┐
│            Core              │
│                              │
│ Models                       │
│ Rules                        │
│ Policies                     │
│ Deduplication                │
└──────────────┬───────────────┘
               │
      ┌────────┴────────┐
      │                 │
┌─────▼──────┐   ┌──────▼──────┐
│ Windows    │   │Infrastructure│
│ Platform   │   │              │
│            │   │ SQLite       │
│ Clipboard  │   │ Files        │
│ Hotkey     │   │ Logging      │
│ Tray       │   │ Settings     │
│ Windowing  │   │              │
└────────────┘   └─────────────┘
```

---

# 34. 第一阶段最终目标

Windows MVP 只需要完成：

```text
✓ Text Clipboard

✓ Clipboard History

✓ Search

✓ Copy Back

✓ Deduplication

✓ SQLite

✓ Global Hotkey

✓ System Tray
```

暂时不做：

```text
✗ Image

✗ File

✗ HTML

✗ Link Metadata

✗ Categories

✗ Sensitive Regex

✗ Auto Update
```

先确保最核心的：

> **Clipboard Capture Pipeline**

稳定。

---

# 35. 下一步开发顺序

建议严格按照以下顺序：

```text
Step 1
创建 WinUI 3 项目

↓

Step 2
建立 Core / Platform / Infrastructure

↓

Step 3
实现 SQLite

↓

Step 4
实现 WM_CLIPBOARDUPDATE

↓

Step 5
实现 Clipboard Text Capture

↓

Step 6
实现 Clipboard Repository

↓

Step 7
实现 History UI

↓

Step 8
实现 Copy Back

↓

Step 9
实现 Search

↓

Step 10
实现 Hotkey + Tray
```

---

# 最终目标

ClipDock 最终形成：

```text
                 ClipDock
                     │
         ┌───────────┴───────────┐
         │                       │
       macOS                  Windows
         │                       │
 Swift + SwiftUI            C# + WinUI 3
         │                       │
  NSPasteboard             Win32 Clipboard
         │                       │
     CoreData                 SQLite
         │                       │
         └───────────┬───────────┘
                     │
              Feature Contract
                     │
         ┌───────────┴───────────┐
         │                       │
       Specs                   Tests
```

> **保持平台原生体验，而不是强行共享 UI；保持核心功能行为一致，而不是强行共享所有代码。**