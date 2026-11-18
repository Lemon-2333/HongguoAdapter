<p align="center">
  <strong>HongguoAdapter</strong><br>
  <em>iPhone Duo · LiveContainer · 红果短剧</em>
</p>

# HongguoAdapter

**Make Hongguo Short Drama use the iPhone Duo inner display properly.**

A small LiveContainer tweak for the foldable iPhone Duo. It is **not** a standalone app, **not** an IPA, and it does not contain or distribute any 红果 short-drama content.

[English](README.md) | [简体中文](README.zh-CN.md)

---

## What it does

Hongguo Short Drama is portrait-first. Inside LiveContainer on the Duo, its window can stay on the outer display, keep a phone-sized layout on the inner display, or place the feed/player in the wrong frame. HongguoAdapter attaches the app window to the active inner scene and adjusts the feed and player layout for the Duo's 951×669 inner display.

It works at runtime; the app itself is not modified.

## Features

- Attach the app's main window to the active inner `UIWindowScene`.
- Reconcile layout after fold/unfold and orientation changes.
- Fit the feed canvas and player controls to the inner display.
- Compensate for the Duo's taller top and bottom safe areas.
- Handle the app's full-screen player and rotation paths.
- HUD with version, runtime log, refresh, copy-log, and hide; after hiding, a small **…** at the top-right restores it.

## Project status

Vibe-coded, app-specific compatibility shim. Tested baseline: **红果短剧 7.3.5** on iPhone Duo. The app's private UIKit class names and layout can change with any update, so other versions, screens, and player flows are not guaranteed. This is not production-grade software; keep a way to disable the tweak if it misbehaves. Issues with a HUD screenshot are welcome.

## Tested baseline

| App | Environment | Status |
| --- | --- | --- |
| 红果短剧 7.3.5 | iPhone Duo + LiveContainer | Inner-display attachment and feed/player layout fixed; HUD available |

No other app or app version is claimed.

## Requirements

- iPhone Duo running a compatible iOS version.
- LiveContainer built with the **iOS 27.2 SDK**. Use the official [3.8.14 nightly](https://github.com/LiveContainer/LiveContainer/releases/tag/nightly) (`DTSDKName=iphoneos27.2`); the older 3.8.11 stable is built with 26.2 and does not expose the Duo layout traits.

## Installation

1. Install LiveContainer and sign it with your own Apple ID.
2. Download `dist/AppAdapter-v36-adaptive.zip` and unzip it.
3. Put `AppAdapter-v36-adaptive.dylib` into LiveContainer's **Tweaks** folder (global or the app-specific folder).
4. Open LiveContainer → **Tweaks** → **Sign** (a valid signing certificate is required).
5. Launch 红果短剧 from LiveContainer. The HUD appears at the top. Use **刷新 / 复制日志 / 隐藏**; after **隐藏**, only a small **…** remains at the top-right — tap it to restore.
6. If the layout is wrong, copy the HUD text and open an issue. Do not re-sign the app itself; the tweak is signed in Tweaks.

## Builds

| Build | File | Notes |
| --- | --- | --- |
| v36 Adaptive | `dist/AppAdapter-v36-adaptive.zip` | Current source build; includes HUD |

SHA-256 (current files):

```text
ec42ef061c5f8f8840f51abd3fc18b3b0429e0db32782194da400e083856f2ac  AppAdapter-v36-adaptive.dylib
450250bf76abd7be1bd204d68b548356add56e14407d34924940b0855feae43c  AppAdapter-v36-adaptive.zip
```

## Build from source

Requirements: macOS with Xcode 27+ / iPhoneOS SDK, `clang`, and `codesign`.

```bash
APP_ADAPTER_IPAD_TEST=1 ./build-app-adapter.sh
# -> dist/AppAdapter-v36-adaptive.dylib
# -> dist/AppAdapter-v36-adaptive.zip
```

`APP_ADAPTER_IPAD_TEST=1` is required for the 红果 adaptive branch. The script ad-hoc signs the dylib; LiveContainer re-signs it on the device.

## Known limitations

- App-specific; class names and layout can break after a 红果 update.
- Portrait-first app: some screens may letterbox on the inner display; the adapter does not add a fill/portrait HUD layout switch.
- Only tested with LiveContainer on iPhone Duo; it is not a general Duo adapter.
- The HUD is diagnostic; hide it for daily use.
- No guarantee for other iOS versions or device configurations.

## Disclaimer

- Free, non-commercial, for learning, interoperability testing, and personal use only.
- Does not contain or distribute the app, its assets, or any cracked content, and provides no download channel for them.
- Not affiliated with, authorized by, or endorsed by 红果短剧, ByteDance, Apple, LiveContainer, or any platform.
- Names, trademarks, and assets belong to their respective owners.
- Provided **as is**, without warranty; it may violate service terms or break after an app/OS update. Evaluate the risks yourself.
- Please support the official app. Rights holders may contact us through an issue.

## License

MIT. See [LICENSE](LICENSE).
