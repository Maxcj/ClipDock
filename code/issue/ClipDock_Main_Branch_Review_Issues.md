# ClipDock main 分支功能审查与隐形问题修改建议

## 1. 审查范围

本次审查基于 `main` 分支当前代码状态，重点关注：

- 新增功能是否形成完整闭环
- 是否存在编译层面的隐形问题
- 设置项与实际行为是否一致
- 自定义分类功能是否稳定
- 真实使用时是否会产生噪音数据
- 发布前 README、迁移、本地化是否完整

当前 `main` 分支已经包含以下关键能力：

- Colors 颜色识别
- 颜色详情预览与 HEX / RGB / RGBA 复制
- 代码语言识别
- 代码高亮与 JSON Actions
- 系统分类显示 / 隐藏
- 自定义分类 CRUD
- 分类拖拽排序
- 记录加入自定义分类
- 自定义分类筛选
- 分类 Badge 展示
- Sparkle 更新检查
- 设置页分类管理入口

整体判断：功能已经比较完整，但当前处于“快速新增功能后的整合阶段”，建议先修复隐形问题，再继续添加新功能。

---

## 2. 总体结论

`main` 分支功能方向是对的，尤其是自定义分类已经从固定 enum 迁移到 CoreData 数据模型，说明分类系统已经具备后续扩展能力。

但是当前存在几类需要优先处理的问题：

```txt
P0：可能导致编译失败或明显行为错误
P1：功能可用，但真实使用会产生体验问题
P2：发布前完善项和架构优化项
```

建议优先修复：

1. 补齐 `ClipboardCodePane` 和 `ClipboardCodeLineCache`
2. 修复图片历史开关对直接复制图片不生效的问题
3. 修复颜色复制 / 代码 Action 复制会被 ClipDock 自己重新记录的问题
4. 修复链接详情页 favicon 显示不一致的问题
5. 收紧代码语言识别规则
6. 优化分类拖拽排序保存时机
7. 补充 README / README.zh-CN

---

# 3. P0：必须优先修复的问题

## 3.1 代码详情页可能编译失败

### 问题描述

`ClipboardDetailViews.swift` 中 `.code` 分支使用了：

```swift
ClipboardCodePane(record: record)
```

`ClipboardCodeSupport.swift` 中 `codeLineCount` 使用了：

```swift
ClipboardCodeLineCache.shared.lines(for: self).count
```

但当前仓库中没有看到 `ClipboardCodePane` 和 `ClipboardCodeLineCache` 的定义。

如果本地也没有未提交文件，Xcode 会直接报错：

```txt
Cannot find 'ClipboardCodePane' in scope
Cannot find 'ClipboardCodeLineCache' in scope
```

### 影响

这是编译级别问题，优先级最高。

### 建议修复

先补一个最小可用版本，保证 main 分支可编译。

建议新增文件：

```txt
ClipboardCodePane.swift
ClipboardCodeLineCache.swift
```

### 最小版 ClipboardCodeLineCache

```swift
final class ClipboardCodeLineCache {
    static let shared = ClipboardCodeLineCache()

    private let cache = NSCache<NSString, NSArray>()

    private init() {
        cache.countLimit = 128
    }

    func lines(for record: ClipboardRecord) -> [String] {
        let key = record.objectID.uriRepresentation().absoluteString as NSString

        if let cached = cache.object(forKey: key) as? [String] {
            return cached
        }

        let text = record.fullText ?? record.displayText ?? ""
        let lines = text.components(separatedBy: .newlines)

        cache.setObject(lines as NSArray, forKey: key)
        return lines
    }

    func remove(for record: ClipboardRecord) {
        let key = record.objectID.uriRepresentation().absoluteString as NSString
        cache.removeObject(forKey: key)
    }
}
```

### 最小版 ClipboardCodePane

```swift
struct ClipboardCodePane: View {
    let record: ClipboardRecord

    private var language: ClipboardCodeLanguage {
        record.codeLanguage
    }

    private var lines: [String] {
        ClipboardCodeLineCache.shared.lines(for: record)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)

                            Text(ClipboardCodeHighlighter.attributedLine(line, language: language))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(14)
            }
            .background(Color.black.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(language.title, systemImage: language.iconSymbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(language.badgeColor)

            Spacer()

            Text("\(lines.count) lines")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
```

---

## 3.2 关闭图片历史后，直接复制图片仍可能被保存

### 问题描述

当前代码对“复制单个图片文件”的场景做了判断：

```swift
guard keepsImageHistory else {
    return .dropped(reason: "image history disabled")
}
```

但是对直接复制图片内容的场景没有判断：

```swift
if let image = NSImage(pasteboard: pasteboard),
   let assets = saveImageAssets(from: image) {
    return .snapshot(...)
}
```

### 影响

用户在 Settings 中关闭 `Keep image history` 后，以下内容仍然可能被记录：

- 截图
- 网页图片
- App 内复制出来的图片
- 设计软件复制的图片内容

这属于设置项与实际行为不一致，也可能带来隐私风险。

### 建议修复

改为：

```swift
if let image = NSImage(pasteboard: pasteboard) {
    guard keepsImageHistory else {
        return .dropped(reason: "image history disabled")
    }

    guard let assets = saveImageAssets(from: image) else {
        return .dropped(reason: "failed to save image assets")
    }

    return .snapshot(ClipboardSnapshot(
        kind: .image,
        displayText: "Image",
        fullText: assets.original.path,
        imagePath: assets.original.path,
        assetPath: nil,
        thumbnailPath: assets.thumbnail.path,
        sourceAppName: appName,
        sourceBundleId: bundleId,
        hash: Self.hash(kind: .image, data: assets.originalData)
    ))
}
```

---

## 3.3 颜色复制 / 代码 Action 复制会被自己重新记录

### 问题描述

`ClipboardMonitor.copy(_:)` 中有自复制抑制逻辑：

```swift
markSuppression(changeCount: pasteboard.changeCount)
```

但是颜色详情页中的复制逻辑直接写剪切板：

```swift
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(value, forType: .string)
```

代码 Action 中也直接写剪切板：

```swift
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(text, forType: .string)
```

这些内部复制动作没有调用 suppression。

### 影响

用户点击以下按钮后，ClipDock 可能会再次捕获这些转换结果：

- Copy HEX
- Copy RGB
- Copy RGBA
- Copy Markdown
- Pretty JSON
- Minify JSON

结果是历史记录里会出现很多 ClipDock 自己产生的新记录。

例如：

```txt
复制 #FF5733
点击 Copy RGB
历史里新增 rgb(255, 87, 51)
点击 Copy RGBA
历史里新增 rgba(255, 87, 51, 1)
```

这会让历史记录变脏。

### 建议修复

把内部复制统一交给 `ClipboardMonitor`。

新增方法：

```swift
extension ClipboardMonitor {
    func copyTextSilently(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markSuppression(changeCount: pasteboard.changeCount)
    }
}
```

如果 `markSuppression` 目前是 `private`，可以把 `copyTextSilently` 写在 `ClipboardMonitor` 内部。

然后颜色复制改为：

```swift
clipboardMonitor.copyTextSilently(value)
```

代码 Action 复制也不要直接写剪切板，而是返回字符串，由调用方通过 `clipboardMonitor.copyTextSilently(...)` 写入。

建议调整：

```swift
enum ClipboardCodeActions {
    static func markdownCodeBlock(_ code: String, language: ClipboardCodeLanguage) -> String {
        ...
    }

    static func prettyJSON(_ code: String) -> String? {
        ...
    }

    static func minifyJSON(_ code: String) -> String? {
        ...
    }
}
```

不要在 `ClipboardCodeActions` 内部直接操作 `NSPasteboard`。

---

# 4. P1：功能可用，但有隐形体验问题

## 4.1 链接详情页显示来源 App 图标，而不是网站 favicon

### 问题描述

项目中已经有：

```swift
var websiteIconImage: NSImage?
```

它用于获取网站 favicon。

但是链接详情页中使用的是：

```swift
if let icon = record.sourceAppIcon {
    Image(nsImage: icon)
}
```

`sourceAppIcon` 是来源 App 图标，例如：

- Safari
- Chrome
- Xcode
- Notes

不是网站 favicon。

### 影响

列表里可能显示网站图标，但详情页显示浏览器图标，体验不一致。

### 建议修复

链接详情页中优先使用 `websiteIconImage`：

```swift
if let icon = record.websiteIconImage {
    Image(nsImage: icon)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
} else if let icon = record.sourceAppIcon {
    Image(nsImage: icon)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
} else {
    Image(systemName: "globe")
}
```

---

## 4.2 SQL / YAML 代码识别误判偏高

### 问题描述

当前 SQL 判断逻辑比较宽，只要命中任意 SQL keyword 就可能识别为 SQL。

当前 YAML 判断也比较宽：

```swift
text.contains(":") && (text.contains("- ") || text.contains("\n"))
```

这会导致很多普通文本被识别成代码。

### 容易误判的例子

```txt
Please update this document.
```

可能因为包含 `UPDATE` 被识别成 SQL。

```txt
Name: Max
Notes: follow up tomorrow
```

可能因为包含冒号和换行被识别成 YAML。

### 影响

普通文本会进入 Code 分类，导致分类结果不准。

### 建议修复 SQL

```swift
private static func isSQL(_ text: String) -> Bool {
    let upper = text.uppercased()
    let trimmed = upper.trimmingCharacters(in: .whitespacesAndNewlines)

    let sqlStarts = [
        "SELECT ",
        "INSERT INTO ",
        "UPDATE ",
        "DELETE FROM ",
        "CREATE TABLE ",
        "ALTER TABLE "
    ]

    let hasSqlStart = sqlStarts.contains { trimmed.hasPrefix($0) }

    let hasSqlStructure =
        upper.contains(" FROM ") ||
        upper.contains(" WHERE ") ||
        upper.contains(" JOIN ") ||
        upper.contains(" SET ") ||
        upper.contains(" VALUES ")

    return hasSqlStart && hasSqlStructure
}
```

### 建议修复 YAML

```swift
private static func isYAML(_ text: String) -> Bool {
    let lines = text
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }

    guard lines.count >= 2 else { return false }

    let yamlLikeLineCount = lines.filter { line in
        line.range(of: #"^[-\s]*[A-Za-z0-9_\-]+\s*:"#, options: .regularExpression) != nil
    }.count

    return yamlLikeLineCount >= 2
}
```

---

## 4.3 分类拖拽排序在 dropEntered 中直接保存 CoreData

### 问题描述

当前拖拽排序在 `dropEntered` 中调用：

```swift
ClipboardCategoryManager.move(draggedCategory, before: target, context: context)
```

而 `move` 内部会执行排序并保存 CoreData。

### 影响

拖动经过多个分类行时，会多次保存数据库。

分类数量少时影响不大，但存在这些隐患：

- 拖拽时卡顿
- 排序抖动
- CoreData 频繁写入
- 未来分类数量变多后体验下降

### 建议修复方向

改成：

```txt
dropEntered：只改 @State 本地数组
performDrop：统一写 sortOrder 并 save
```

建议在 `ClipboardCategorySettingsView` 中维护本地数组：

```swift
@State private var orderedCategories: [ClipboardCategory] = []
@State private var draggedCategoryID: UUID?
```

拖拽过程中只做：

```swift
orderedCategories.move(...)
```

松手后：

```swift
for (index, category) in orderedCategories.enumerated() {
    category.sortOrder = Int32(index * 10)
    category.updatedAt = Date()
}
try viewContext.save()
```

---

## 4.4 系统分类名称不会跟随语言切换

### 问题描述

系统分类默认名称写入 CoreData 时是英文：

```swift
defaultName: "All"
defaultName: "Text"
defaultName: "Links"
```

`resolvedName` 又优先使用 CoreData 中的 `name`，因此中文界面下系统分类仍可能显示英文。

### 影响

切换语言后，系统分类名称不会变化，体验不一致。

### 建议修复

系统分类名称不要直接依赖持久化的 `name`。

建议给 `SystemClipboardCategoryKey` 增加本地化 key：

```swift
extension SystemClipboardCategoryKey {
    var textKey: AppTextKey {
        switch self {
        case .all: return .all
        case .text: return .text
        case .links: return .links
        case .images: return .images
        case .code: return .code
        case .files: return .files
        case .colors: return .colors
        case .other: return .other
        }
    }
}
```

然后修改 `resolvedName`：

```swift
var resolvedName: String {
    if categoryType == .system, let key = systemCategoryKey {
        return AppLocalizer.current.text(key.textKey)
    }

    let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? AppLocalizer.current.text(.categories) : trimmed
}
```

如果未来允许用户重命名系统分类，则需要增加一个字段：

```txt
customDisplayName: String?
```

而不是直接覆盖系统默认名称。

---

## 4.5 Updates 入口被隐藏在 About 中

### 问题描述

当前 `SettingsTab` 没有独立的 Updates tab，更新检查相关设置被放在 About 中。

### 影响

用户想检查更新时，可能不知道要进入 About。

### 建议修复

推荐恢复独立 Updates tab。

```swift
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case privacy
    case quickOpen
    case storage
    case categories
    case updates
    case about
}
```

然后 SettingsView 中拆分：

```swift
case .updates:
    updatesSettingsPane

case .about:
    aboutSettingsPane
```

如果不想恢复独立 tab，至少把 About 显示名称改成：

```txt
About & Updates
```

---

# 5. P2：后续优化和发布前完善

## 5.1 分类设置页建议拆成 System / Custom 两个 section

### 问题描述

当前分类设置页中，系统分类和自定义分类混在一个列表里。

虽然系统分类不能删除，自定义分类可以编辑删除，但用户理解成本较高。

### 建议结构

```txt
Categories

System Categories
- All
- Text
- Links
- Images
- Code
- Files
- Colors
- Other

Custom Categories
- Work
- API
- Design
- Important
+ Add Category
```

### 好处

- 用户更容易理解系统分类和自定义分类的区别
- 系统分类只做显示隐藏 / 排序
- 自定义分类支持编辑 / 删除 / 颜色 / 图标
- 后续可以分别做文案说明

---

## 5.2 分类分配弹窗的限制提示文案不够准确

### 问题描述

当前分类分配弹窗底部一直显示“最多 3 个分类”的限制提示，即使用户没有达到限制也显示。

### 建议方案 A：只在达到限制后显示

```swift
if !ClipboardCategoryManager.canAssignAdditionalCategory(record: record, context: viewContext) {
    Text(localizer.text(.categoryLimitReached, ClipboardCategoryManager.maxCustomCategoriesPerRecord))
}
```

### 建议方案 B：改成中性提示

```txt
Each item can belong to up to 3 custom categories.
```

中文：

```txt
每条记录最多可以加入 3 个自定义分类。
```

---

## 5.3 README 没有同步 main 分支新功能

### 问题描述

当前 README 仍然只描述基础能力，没有体现 main 分支已经完成的新功能。

### 建议补充英文 README

```md
## Features

- Menu bar first workflow
- Global hotkey to show or hide the main window
- Clipboard history for text, links, images, files, code snippets, and colors
- Custom categories with visibility control and drag-to-reorder
- Assign clipboard items to up to 3 custom categories
- Color detection for HEX, RGB, RGBA, HSL, and HSLA
- One-click color copy as HEX, RGB, or RGBA
- Code language detection and lightweight syntax highlighting
- Code actions: Copy as Markdown, Pretty JSON, Minify JSON
- Rich previews for links, images, files, colors, and code
- Sensitive content filters for verification codes, passwords, tokens, private keys, and long secret-like text
- Localized UI in English and Simplified Chinese
```

### 建议补充中文 README

```md
## 功能特性

- 菜单栏优先的轻量工作流
- 全局快捷键快速显示或隐藏主窗口
- 支持文本、链接、图片、文件、代码片段和颜色历史
- 支持自定义分类，可控制显示隐藏并拖拽排序
- 每条剪切板记录最多可加入 3 个自定义分类
- 自动识别 HEX、RGB、RGBA、HSL、HSLA 颜色
- 一键复制 HEX、RGB、RGBA 颜色格式
- 自动识别代码语言并提供轻量语法高亮
- 支持代码操作：复制为 Markdown、格式化 JSON、压缩 JSON
- 为链接、图片、文件、颜色和代码提供丰富预览
- 支持敏感内容过滤：验证码、密码、Token、私钥和长敏感文本
- 支持英文和简体中文界面
```

---

## 5.4 CoreData 模型建议启用版本管理

### 问题描述

当前 CoreData 模型已经从单一 `ClipboardRecord` 扩展为：

```txt
ClipboardRecord
ClipboardCategory
ClipboardRecordCategory
```

并且 `ClipboardRecord` 新增了：

```txt
pinnedAt
categoryLinks
```

后续如果继续新增字段，例如：

```txt
codeLanguageRaw
colorHex
colorRed
colorGreen
colorBlue
colorAlpha
categoryRule
```

迁移会越来越复杂。

### 建议

发布前开始使用 versioned CoreData model：

```txt
ClickDock.xcdatamodeld
├── ClickDock_v1.xcdatamodel
├── ClickDock_v2.xcdatamodel
└── current version = ClickDock_v2
```

并保留轻量迁移配置：

```swift
container.persistentStoreDescriptions.first?.shouldMigrateStoreAutomatically = true
container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true
```

---

## 5.5 `ClipboardFilter` 可以逐步下线

### 问题描述

当前已经有新的：

```swift
ClipboardCategorySelection
SystemClipboardCategoryKey
ClipboardCategory
```

但旧的 `ClipboardFilter` 仍然存在，并通过 extension 转换到 system category。

### 影响

短期可以作为兼容层，但长期同时维护两套分类概念会增加复杂度。

### 建议

逐步替换：

```swift
ClipboardFilter
```

为：

```swift
ClipboardCategorySelection
```

最终让 `ClipboardFilter` 只保留在迁移层，或者彻底删除。

---

## 5.6 代码语言和颜色数据建议持久化

### 问题描述

当前代码语言和颜色信息多为运行时检测：

```swift
record.codeLanguage
record.clipboardColorValue
```

如果历史记录很多，UI 滚动时会反复检测。

### 建议新增字段

```txt
codeLanguageRaw: String?
colorHex: String?
colorRed: Double
colorGreen: Double
colorBlue: Double
colorAlpha: Double
colorSourceFormat: String?
```

保存剪切板时一次识别，展示时直接读取。

### 好处

- 降低列表滚动时的重复计算
- 方便后续搜索颜色
- 方便统计代码语言
- 方便按颜色格式筛选
- 方便做颜色复制历史增强

---

# 6. 推荐修改顺序

## 第一批：保证功能闭环

```txt
1. 补 ClipboardCodePane
2. 补 ClipboardCodeLineCache
3. 修复直接复制图片不受 keepImages 控制
4. 统一颜色复制 / 代码 Action 复制的 self-copy suppression
5. 链接详情页优先显示 websiteIconImage
```

## 第二批：降低误判和体验问题

```txt
1. 收紧 SQL / YAML 识别规则
2. 分类设置页拆成 System / Custom 两个 section
3. 恢复 Updates 独立 Tab
4. 系统分类名称改成动态本地化
5. 分类分配弹窗提示文案改为准确提示
```

## 第三批：发布前完善

```txt
1. README / README.zh-CN 同步新功能
2. CoreData 模型启用版本管理
3. 下线 ClipboardFilter 旧抽象
4. 持久化 codeLanguageRaw 和颜色结构化字段
5. 拖拽排序改成本地数组移动，performDrop 再保存
```

---

# 7. 发布前检查清单

## 编译检查

```txt
[ ] main 分支完整编译通过
[ ] Debug / Release 都能构建
[ ] Xcode 中所有新增 Swift 文件都加入 Target Membership
[ ] ClipboardCodePane 存在
[ ] ClipboardCodeLineCache 存在
```

## 剪切板行为检查

```txt
[ ] 复制普通文本可以正常记录
[ ] 复制 URL 可以进入 Links
[ ] 复制代码可以进入 Code
[ ] 复制颜色可以进入 Colors
[ ] 关闭图片历史后，截图不会被记录
[ ] 关闭文件历史后，文件不会被记录
[ ] 点击 Copy HEX / RGB / RGBA 不会新增自复制历史
[ ] 点击 Pretty JSON / Minify JSON 不会新增自复制历史
```

## 分类功能检查

```txt
[ ] 系统分类可以显示 / 隐藏
[ ] All 不允许隐藏
[ ] 自定义分类可以新增
[ ] 自定义分类可以编辑
[ ] 自定义分类可以删除
[ ] 删除自定义分类不会删除剪切板记录
[ ] 记录可以加入自定义分类
[ ] 每条记录最多只能加入 3 个自定义分类
[ ] 点击自定义分类可以正确筛选记录
[ ] 搜索 + 自定义分类筛选可以组合生效
[ ] 拖拽排序后重启仍然保留顺序
```

## 本地化检查

```txt
[ ] 英文界面系统分类显示英文
[ ] 中文界面系统分类显示中文
[ ] 自定义分类名称不被自动翻译
[ ] Categories 设置页文案完整
[ ] 删除分类确认文案完整
[ ] 分类限制提示文案准确
```

## 发布资料检查

```txt
[ ] README.md 已同步新功能
[ ] README.zh-CN.md 已同步新功能
[ ] 截图包含 Categories 设置页
[ ] Release Notes 写明 Colors / Code / Categories
[ ] appcast.xml 版本信息正确
```

---

# 8. 最终建议

当前 `main` 分支已经进入产品功能成型阶段，尤其是自定义分类系统已经基本落地。

但现在不建议继续马上加新功能，应该先进入一次“稳定性整理”：

```txt
先保证能编译
再保证设置项行为一致
再避免自复制污染历史
再降低代码识别误判
最后补 README 和发布资料
```

优先修复 P0 问题后，这个版本就可以作为一次比较完整的功能版本发布。
