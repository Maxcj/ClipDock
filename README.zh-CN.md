# ClipDock

ClipDock 是一款轻量级的 macOS 剪贴板管理器，专注于快速收集、快速回溯和低摩擦复用。

它运行在菜单栏中，不会占用 Dock，并且可以通过全局快捷键快速唤出主窗口。

## 截图

![ClipDock 主窗口](images/ClipDock.png)

![设置 - 通用](images/Setting_general.png)
![设置 - 隐私](images/Setting_privacy.png)
![设置 - 快速打开](images/Setting_quick_open.png)
![设置 - 存储](images/Setting_storage.png)
![设置 - 更新](images/Setting_update.png)
![设置 - 关于](images/Setting_about.png)

## 功能

- 菜单栏优先的工作方式
- 全局快捷键显示或隐藏主窗口
- 支持文本、链接、图片、文件、代码片段和颜色的剪贴板历史
- 支持链接、图片、文件、颜色和代码的丰富预览
- 支持自定义分类，可控制显示隐藏并拖拽排序
- 每条剪贴板记录最多可加入 3 个自定义分类
- 支持一键复制 HEX、RGB、RGBA 颜色
- 支持代码语言识别与轻量语法高亮
- 支持代码操作：复制为 Markdown、格式化 JSON、压缩 JSON
- 支持复制、置顶、删除、排除来源应用等快捷操作
- 每条记录附带元信息，便于更快浏览和定位
- 支持英文和简体中文界面

## 剪贴板历史

- 文本、链接、图片、文件、代码片段和颜色都会自动记录
- 可以在设置中开启或关闭图片历史
- 可以在设置中开启或关闭文件历史
- 颜色复制和代码格式化操作不会污染历史记录
- 可以在设置中过滤敏感剪贴板内容
- 可以在更新页忽略某个指定版本

## 更新

ClipDock 使用 [Sparkle](https://sparkle-project.org/) 提供自动更新能力。

更新发布拆分为 GitHub 的两个部分：

- GitHub Releases 用于存放可下载的应用压缩包
- GitHub Pages 用于托管 `appcast.xml`
- Sparkle 负责更新检测、下载、校验和安装

更新订阅地址：

`https://maxcj.github.io/ClipDock/appcast.xml`

## 开始使用

1. 下载或自行构建 ClipDock。
2. 启动应用，并在 macOS 提示时允许访问剪贴板。
3. 使用菜单栏图标或全局快捷键打开主窗口。
4. 打开设置，调整历史保留、内容过滤和更新偏好。

## 构建

环境要求：

- macOS 13.2 或更高版本
- Xcode 14.3 或更高版本

在 Xcode 中打开 `code/ClickDock/ClickDock.xcodeproj`，然后构建 `ClickDock` scheme。

## 发布说明

已发布版本的说明存放在：

`docs/release-notes/<version>/`

## 项目结构

- `code/ClickDock/ClickDock/` 应用源码
- `docs/` GitHub Pages 资源和 appcast 订阅文件
- `scripts/` 发布相关辅助脚本
- `icon/` 应用图标源文件
- `ui/` 截图和界面参考

## 许可证

查看 [LICENSE](LICENSE)。
