<p align="center">
  <strong>HongguoAdapter</strong><br>
  <em>iPhone Duo · LiveContainer · 红果短剧</em>
</p>

# HongguoAdapter

**让红果短剧正确使用 iPhone Duo 的内屏。**

这是一个给折叠屏 iPhone Duo 用的小型 LiveContainer tweak。它**不是**独立 App，**不是** IPA，也不包含、不分发任何红果短剧内容。

[English](README.md) | [简体中文](README.zh-CN.md)

---

## 它做什么

红果短剧是竖屏优先的 App。在 Duo 的 LiveContainer 里，它的窗口可能留在外屏、在内屏保持手机尺寸，或者把信息流/播放器放进错误的位置。HongguoAdapter 会把 App 主窗口挂到当前内屏 scene，并按 Duo 的 951×669 内屏调整信息流和播放器布局。

它只在运行时生效，不修改 App 本身。

## 功能

- 把 App 主窗口挂到当前内屏 `UIWindowScene`。
- 折叠/展开、横竖屏变化后重新对齐布局。
- 把信息流画布和播放器控件适配到内屏。
- 补偿 Duo 更高的顶部/底部安全区。
- 处理 App 的全屏播放器和旋转路径。
- HUD：版本、布局状态、快照/复制、隐藏，以及 **竖屏 / 铺满** 切换。

## 项目状态

这是 vibe coding 出来的、针对单个 App 的兼容 shim。实测基线：**红果短剧 7.3.5** + iPhone Duo。App 的私有 UIKit 类名和布局会随更新变化，其他版本、页面和播放器路径不保证可用。它不是生产级软件；如果出现异常，请保留禁用 tweak 的办法。欢迎带 HUD 截图提 issue。

## 实测基线

| App | 环境 | 状态 |
| --- | --- | --- |
| 红果短剧 7.3.5 | iPhone Duo + LiveContainer | 内屏挂载、信息流/播放器布局已修复；HUD 可用 |

不声称支持其他 App 或版本。

## 前提

- iPhone Duo，系统版本兼容。
- LiveContainer 必须使用 **iOS 27.2 SDK** 编译。请使用官方 [3.8.14 nightly](https://github.com/LiveContainer/LiveContainer/releases/tag/nightly)（`DTSDKName=iphoneos27.2`）；旧的 3.8.11 stable 是 26.2，拿不到 Duo 布局 trait。

## 安装

1. 安装 LiveContainer，并用自己的 Apple ID 完成签名。
2. 下载 `dist/AppAdapter-v36-adaptive.zip` 并解压。
3. 把 `AppAdapter-v36-adaptive.dylib` 放进 LiveContainer 的 **Tweaks** 文件夹（全局或单个 App 的目录）。
4. 打开 LiveContainer → **Tweaks** → 点 **签名**（需要有效签名证书）。
5. 从 LiveContainer 启动红果短剧。顶部会出现 HUD；点 **隐藏** 收起（右上角小 **…** 恢复），用 **竖屏 / 铺满** 切换信息流布局。
6. 如果布局不对，复制 HUD 文本后提 issue。不要重签目标 App，tweak 在 Tweaks 里签名即可。

## 构建

| 版本 | 文件 | 说明 |
| --- | --- | --- |
| v36 Adaptive | `dist/AppAdapter-v36-adaptive.zip` | 当前源码构建；含 HUD |

当前文件 SHA-256：

```text
ec42ef061c5f8f8840f51abd3fc18b3b0429e0db32782194da400e083856f2ac  AppAdapter-v36-adaptive.dylib
450250bf76abd7be1bd204d68b548356add56e14407d34924940b0855feae43c  AppAdapter-v36-adaptive.zip
```

## 从源码构建

需要 macOS、Xcode 27+ / iPhoneOS SDK、`clang` 和 `codesign`。

```bash
APP_ADAPTER_IPAD_TEST=1 ./build-app-adapter.sh
# -> dist/AppAdapter-v36-adaptive.dylib
# -> dist/AppAdapter-v36-adaptive.zip
```

红果适配分支必须带 `APP_ADAPTER_IPAD_TEST=1`。脚本会对 dylib 做 ad-hoc 签名；装进 LiveContainer 后由它重新签名。

## 已知限制

- 只针对这个 App；红果更新后类名/布局可能失效。
- App 是竖屏优先：部分页面在内屏会留黑边；**铺满** 可能裁切，**竖屏** 更清晰。
- 只在 iPhone Duo + LiveContainer 上验证过，不是通用 Duo 适配器。
- HUD 是诊断工具，日常使用建议隐藏。
- 不保证其他 iOS 版本或设备配置。

## 免责声明

- 免费、非商业，仅供学习交流、互操作测试和个人使用。
- 不包含、不分发 App 本体、素材或任何破解内容，也不提供下载渠道。
- 与红果短剧、字节跳动、Apple、LiveContainer 及任何平台无关联，未获授权或认可。
- 名称、商标与素材版权归各自权利人。
- 按“现状”提供，不附带担保；可能违反某些服务条款，或因 App/系统更新失效，请自行评估风险。
- 请支持正版；权利人可通过 issue 联系处理。

## License

MIT，见 [LICENSE](LICENSE)。
