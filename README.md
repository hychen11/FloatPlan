# FloatPlan

**像弹幕一样浮在屏幕上的 Mac 待办清单。** 半透明、不挡鼠标、按完成情况自动配色，定时用弹幕提醒你该做什么。

[English](#english) · [下载](https://github.com/hychen11/FloatPlan/releases/latest) · [☕ 请作者喝杯咖啡](#-请作者喝杯咖啡)

![FloatPlan 预览：左边是默认样式，右边是背景全透明、文字 60%](docs/preview.png)

## 为什么做这个

市面上的悬浮便签/待办，大多是一个**普通的置顶窗口**：会挡住下面的内容，一不小心就点到；而且只分“完成 / 没完成”，看不出现在该做哪件。

FloatPlan 想要的是：任务清单一直在视线里，但**像弹幕一样点不到、不打扰**，一眼就能看出“做完了什么、正在做什么、还剩什么”。

## 功能

- **三种状态，一眼看清**
  - ✓ 已完成：灰色 + 删除线
  - ▶ 进行中：黑色加粗
  - ○ 未开始：蓝色
- **点穿，不误触**：鼠标直接穿过悬浮层，点到下面的窗口
- **所有桌面都在**：切换桌面空间、全屏 App 里也能看到
- **快捷键编辑**：`⌥⌘P` 切换编辑模式，改完再按一次回到点穿状态
- **透明度滑块**：背景浓度、文字浓度分别调，拖动时实时预览
- **弹幕提醒**：每 15 / 30 / 60 分钟，当前任务以大字弹幕从屏幕飘过，同时发系统通知

![弹幕提醒](docs/danmaku.png)

## 安装

1. 到 [Releases](https://github.com/hychen11/FloatPlan/releases/latest) 下载 `FloatPlan.zip`，解压后把 `FloatPlan.app` 拖进「应用程序」。
2. **第一次打开**会被系统拦下（因为没有付费开发者签名），任选一种方法放行：
   - 打开「系统设置 → 隐私与安全性」，在下方找到 FloatPlan，点「仍要打开」。
   - 或在终端运行：
     ```bash
     xattr -dr com.apple.quarantine /Applications/FloatPlan.app
     ```
3. 打开后悬浮层出现在屏幕右上角，菜单栏多一个 ☑ 图标。

要求 macOS 13 或更高，支持 Apple 芯片和 Intel。

## 使用

| 操作 | 方法 |
|---|---|
| 进入 / 退出编辑 | `⌥⌘P`，或菜单栏 ☑ → 编辑任务 |
| 切换状态 | 编辑模式下点任务左侧图标：未开始 → 进行中 → 已完成 |
| 添加任务 | 编辑模式最后一行输入，回车 |
| 调顺序 / 删除 | 编辑模式下点 ↑ ↓ ✕ |
| 移动位置 | 编辑模式下拖动顶部「⠿ 拖动这里」 |
| 调透明度 | 菜单栏 ☑ → 背景浓度 / 文字浓度滑块 |
| 定时提醒 | 菜单栏 ☑ → 定时提醒 |

> 刘海屏 MacBook 上，如果菜单栏图标太多，☑ 可能被刘海挡住，用 `⌥⌘P` 也一样。

任务保存在 `~/Library/Application Support/FloatPlan/tasks.json`，纯本地，不联网、不收集任何数据。

## 从源码编译

不需要 Xcode，只要命令行工具：

```bash
xcode-select --install
```

```bash
git clone https://github.com/hychen11/FloatPlan.git
```

```bash
cd FloatPlan && ./build.sh && open build/FloatPlan.app
```

`./build.sh universal` 会同时编译 Apple 芯片和 Intel 版本。

## 计划

- [ ] 每日自动重置 / 历史记录
- [ ] 多份清单切换
- [ ] 自定义颜色和字号
- [ ] 开机自动启动
- [ ] 上架 Mac App Store

欢迎提 [Issue](https://github.com/hychen11/FloatPlan/issues) 和 PR。

## ☕ 请作者喝杯咖啡

如果 FloatPlan 帮你多完成了几件事，欢迎请我喝杯咖啡，这会让我更有动力继续更新。

<!-- 填好链接后把对应行取消注释即可
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-ffdd00?logo=buymeacoffee&logoColor=black)](https://www.buymeacoffee.com/你的用户名)
[![爱发电](https://img.shields.io/badge/爱发电-946ce6)](https://afdian.com/a/你的用户名)

<img src="docs/donate/wechat.png" width="200" alt="微信赞赏码"> <img src="docs/donate/alipay.png" width="200" alt="支付宝收款码">
-->

不方便的话，点一个 ⭐ Star 也是很大的支持！

## English

FloatPlan is a translucent, click-through to-do overlay for macOS. Tasks are colored by status (done / in progress / to do), it stays on every Space and over full-screen apps, and it can remind you of the current task with a bullet-comment style banner that flies across the screen. Press `⌥⌘P` to edit. Download from [Releases](https://github.com/hychen11/FloatPlan/releases/latest); see the install notes above for opening an unsigned app.

## License

[MIT](LICENSE)
