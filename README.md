# 键桥 / KeyBridge

A small macOS menu bar app that shares a MacBook’s keyboard and built-in trackpad with another Mac. Install **the same app on both Macs**, choose **Device → Apply to**, and keep your display-connected mouse available for switching and recovery.

一个菜单栏小工具，把 MacBook 的键盘与内置触摸板应用到另一台 Mac。两台安装同一个软件，在「**设备 → 应用于**」中选择，显示器连接的外置鼠标保留本机使用。

**macOS 14+ · Apple Silicon beta · English / 简体中文 · MIT**

[Download v0.2.0-beta.1](https://github.com/winglight9/KeyBridge/releases/tag/v0.2.0-beta.1) · [Setup / 安装与使用](docs/setup.md) · [Architecture](docs/architecture.md) · [Security](SECURITY.md)

## What works / 当前状态

| Input or connection | Status / 状态 |
| --- | --- |
| Bluetooth typing, pointer movement, clicks and dragging | User verified on an M1 Pro MacBook and M4 Mac mini / 用户已实测 |
| Two-finger scrolling / 双指滚动 | User verified / 用户已实测 |
| Direct cable through Thunderbolt Bridge / 雷雳网桥有线直连 | Implemented; physical cable acceptance testing pending / 已实现，待线材实测 |
| Native pinch, rotation and three/four-finger gestures / 原生捏合、旋转和三／四指手势 | Experimental; disabled by default; physical behavior unverified / 实验功能，默认关闭，待实机确认 |
| Touch ID, FileVault/pre-login input and Force Touch actions | Unsupported / 不支持 |
| Fn/media keys and other Mac/OS combinations | Compatibility not established / 兼容性尚未确认 |

Native gesture forwarding preserves the gesture event for the destination Mac and its apps to interpret. It does **not** replace gestures with preset keyboard shortcuts. Whether a gesture is recognized, and the resulting action, still depend on the destination system, settings and app. The experimental path uses undocumented macOS behavior; it is not a guarantee of complete gesture support.

原生手势转发把事件交给目标 Mac 及应用识别，不把四指上滑等手势写死成快捷键。能否识别以及执行什么操作，取决于目标系统、设置和应用。实验路径依赖未公开的 macOS 行为，不能据此承诺全部手势可用。

## Connect in a few clicks / 几步连接

1. Install and open KeyBridge on both Macs. Device labels use each Mac’s current local network name; pairing identity remains separate from that name.
2. Grant permissions: **source Mac → Input Monitoring + Accessibility**; **destination Mac → Accessibility**. Allow Bluetooth on both for Bluetooth mode. Allow local-network access when macOS requests it for wired discovery.
3. Select **Direct cable** or **Bluetooth**. A new installation defaults to wired; your last manual choice is retained. There is no Wi-Fi or silent transport fallback.
4. Compare the six-digit pairing code and approve on **both** Macs.
5. Select the source under **Device**, then the destination under **Apply to**. Both popovers edit the same route. Select the source as its own destination, or click **Stop forwarding**, to return input locally.

两台打开软件并授权 → 选择链路 → 核对两边六位配对码 → 选择「设备」和「应用于」。用鼠标即可操作，不依赖快捷键。中文系统默认中文，其余默认英文，也可在菜单中手动切换。

For a direct cable, use a **Thunderbolt-capable cable and ports** that establish Thunderbolt Bridge networking. USB-C describes the connector; an arbitrary C-to-C charging/data cable is not sufficient. KeyBridge reports observed configuration, link and network states. A missing link by itself cannot identify the cable’s exact capabilities. See [wired diagnosis](docs/setup.md#wired-diagnosis--有线诊断).

有线需要能建立雷雳网桥网络的线材及接口，不能仅凭两端都是 Type-C 判断。软件会显示配置、链路与网络状态；只看到「未检测到链路」时，无法直接断定线材不支持。

## Recovery and privacy / 恢复与隐私

- The recognized built-in input source is forwarded; external and unidentified pointer sources stay local. Physical sender identification depends on optional, undocumented macOS accessors and fails closed when unavailable.
- **Stop forwarding**, **Retry**, transport switching and disconnect are mouse-clickable. A transport change pauses forwarding and needs confirmation. Retry reconnects the saved device but does not silently resume input forwarding.
- Disconnect, sleep, stale-link detection and capture errors stop interception and release remote pressed keys/buttons. Emergency return: **Control–Option–Command–Escape**.
- Pairing requires bilateral approval and pins peer identities. Input travels through an authenticated encrypted session. No cloud account or relay is used.
- Diagnostics contain connection state, device names, permissions and counters, but no typed text or raw gesture payloads. Review device/network details before sharing diagnostics publicly.

断线或异常会停止转发并释放远端按键；外置鼠标可用于点击恢复。输入不经过云端。诊断不记录键入内容或原始手势，但可能包含设备名和本地网络信息，公开前请检查。

## Install and trust / 安装与信任

The downloadable beta is **locally signed**, not signed with an Apple Developer ID and **not Apple-notarized**. macOS may block its first launch. Review the source and release notes, then follow the per-app instructions in [setup](docs/setup.md); do not disable system-wide security. Keep the installed app at `/Applications/KeyBridge.app` before granting permissions. Current release packaging targets Apple Silicon; Intel has not been verified.

当前测试包使用本地开发证书签名，没有 Apple Developer ID 签名和 Apple 公证，首次打开可能被系统拦截。请先确认来源，再按[安装说明](docs/setup.md)处理当前应用，勿关闭系统整体安全机制。先放到「应用程序」再授权，有助于避免重复授权。当前安装包面向 Apple Silicon，Intel 尚未验证。

## Build from source

Requirements: macOS 14+, a Swift 6-capable Xcode/Command Line Tools installation and Python 3 for the packaging helpers. There are no third-party Swift package dependencies.

```sh
# Build and package without launching or replacing a running app
KEYBRIDGE_CONFIGURATION=release ./script/build_and_run.sh --build-only

# Build and launch the development app
./script/build_and_run.sh

# Run protocol and diagnostic checks explicitly
./script/test.sh
```

The script stages `outputs/KeyBridge.app`. `--verify`, `--logs`, `--telemetry` and `--debug` support development workflows. The packaging helper maintains a local development signing identity under ignored `work/signing/`; never publish that directory. Supply `KEYBRIDGE_SIGN_IDENTITY` to select your own signing identity. Apple notarization is a separate distribution step and is not performed automatically.

A project-local toolchain overlay handles specific stale SwiftPM interfaces/duplicate module maps in the development machine’s Command Line Tools. It does not edit the system toolchain. The check runner is a Swift executable and does not require XCTest. See [architecture](docs/architecture.md) for security, input capture and validation boundaries.

## Feedback / 反馈

Use [GitHub Issues](https://github.com/winglight9/KeyBridge/issues) for reproducible bugs. Include the app version, both Mac models/macOS versions, connection mode and redacted diagnostics. For gesture reports, name the gesture and destination app; distinguish a physical input test from a remote-control or synthetic event test.

反馈请附版本、两台机型和系统版本、连接方式及脱敏诊断。手势问题请说明手势和目标应用，并区分真实触摸板操作与远程工具产生的输入。

[MIT License](LICENSE). Security-sensitive reports: see [SECURITY.md](SECURITY.md).
