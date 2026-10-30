# 键桥 / KeyBridge

A small macOS menu bar app that shares a MacBook’s keyboard and built-in trackpad with another Mac. Install **the same app on both Macs**, choose **Device → Apply to**, and keep your display-connected mouse available for switching and recovery.

一个菜单栏小工具，把 MacBook 的键盘与内置触摸板应用到另一台 Mac。两台安装同一个软件，在「**设备 → 应用于**」中选择，显示器连接的外置鼠标保留本机使用。

**macOS 14+ · Apple Silicon beta · English / 简体中文 · MIT**

[Download v1.5](https://github.com/winglight9/KeyBridge/releases/tag/v1.5) · [Setup / 安装与使用](docs/setup.md) · [Architecture](docs/architecture.md) · [Security](SECURITY.md)

## What works / 当前状态

| Input or connection | Status / 状态 |
| --- | --- |
| Bluetooth typing, pointer movement, clicks and dragging | User verified on an M1 Pro MacBook and M4 Mac mini / 用户已实测 |
| Two-finger scrolling / 双指滚动 | User verified / 用户已实测 |
| Direct cable through Thunderbolt Bridge / 雷雳网桥有线直连 | User verified in the setup below / 已在下述组合实测 |
| Native multi-finger gestures and source trackpad isolation / 原生多指手势与来源触摸板隔离 | User confirmed working over the wired link below; experimental option remains off by default / 用户已确认下述有线组合正常；实验选项仍默认关闭 |
| Wired microphone sharing / 有线麦克风共享 | New in 1.2; experimental, off by default; physical acceptance pending / 1.2 新增实验功能，默认关闭，待实机验收 |
| Touch ID, FileVault/pre-login input and Force Touch actions | Unsupported / 不支持 |
| Fn/media keys and other Mac/OS combinations | Compatibility not established / 兼容性尚未确认 |

**Physical acceptance scope (2026-10-29):** the user confirmed wired input, multi-finger gestures, source trackpad isolation and external-mouse behavior on an **M1 Pro MacBook → M4 Mac mini, both running macOS 15.8.1**. This is a result for that setup, not a compatibility guarantee for every Mac, OS, app or gesture. Earlier Bluetooth checks covered typing, pointer movement, clicks, dragging and two-finger scrolling.

**实测范围（2026-10-29）：** 用户已确认 **M1 Pro MacBook → M4 Mac mini、两台 macOS 15.8.1** 的有线输入、多指手势、来源触摸板隔离及外置鼠标表现正常。该结论仅针对这套组合，不代表所有机型、系统、应用或每一种手势均已验证。此前蓝牙实测覆盖打字、指针、点击、拖动和双指滚动。

Native gesture forwarding preserves the gesture event for the destination Mac and its apps to interpret. It does **not** replace gestures with preset keyboard shortcuts. Whether a gesture is recognized, and the resulting action, still depend on the destination system, settings and app. The experimental path uses undocumented macOS behavior; it is not a guarantee of complete gesture support.

原生手势转发把事件交给目标 Mac 及应用识别，不把四指上滑等手势写死成快捷键。能否识别以及执行什么操作，取决于目标系统、设置和应用。实验路径依赖未公开的 macOS 行为，不能据此承诺全部手势可用。

## Connect in a few clicks / 几步连接

1. Install and open KeyBridge on both Macs. Device labels use each Mac’s current local network name; pairing identity remains separate from that name.
2. Grant permissions: **source Mac → Input Monitoring + Accessibility**; **destination Mac → Accessibility**. Allow Bluetooth on both for Bluetooth mode. Allow local-network access when macOS requests it for wired discovery.
3. Select **Direct cable** or **Bluetooth**. A new installation defaults to wired; your last manual choice is retained. There is no Wi-Fi or silent transport fallback.
4. Compare the six-digit pairing code and approve on **both** Macs.
5. Select the source under **Device**, then the destination under **Apply to**. Both popovers edit the same route. Select the source as its own destination, or click **Stop forwarding**, to return input locally.

两台打开软件并授权 → 选择链路 → 核对两边六位配对码 → 选择「设备」和「应用于」。用鼠标即可操作，不依赖快捷键。中文系统默认中文，其余默认英文，也可在菜单中手动切换。

## Recommended connection and cable / 推荐连接与线材

**Use wired for daily work. Bluetooth has noticeable latency, especially with the trackpad; use it temporarily or as a backup.** It remains a manually selected mode, with no silent fallback.

**日常使用推荐有线。蓝牙延迟较高，触摸板上尤其明显，建议仅临时使用或备用。** 连接方式由你手动选择，不会悄悄切换。

- Choose a **certified Thunderbolt 3 or Thunderbolt 4 USB-C cable** and connect it directly to a Thunderbolt port on each Mac. A USB4 cable is an option only when its manufacturer explicitly confirms Thunderbolt compatibility; a “USB4” label alone is not our purchase criterion.
- **Mac mini (2024, M4/M4 Pro): use a rear port.** M4 has three rear Thunderbolt 4 ports; M4 Pro has three rear Thunderbolt 5 ports. The two front USB-C ports are USB 3 up to 10 Gb/s and do not provide the Thunderbolt connection required here.
- “USB-C,” “full-featured,” “100 W/240 W,” video support or “10 Gb/s” alone does not establish Thunderbolt networking support. Charging power and connector shape are not enough.

- 优先购买明确标注认证的 **雷雳 3 / Thunderbolt 3 或雷雳 4 / Thunderbolt 4 双 USB-C 线**，两端直接插入两台 Mac 的雷雳接口。USB4 线需由厂商明确说明兼容雷雳，不能只看“USB4”字样。
- **Mac mini（2024，M4 / M4 Pro）必须接背面接口。** M4 背面为三个雷雳 4，M4 Pro 背面为三个雷雳 5；前面两个 USB-C 仅支持最高 10 Gb/s 的 USB 3，不提供这里所需的雷雳连接。
- 仅写“全功能 Type-C”“100 W / 240 W”“支持视频”“10 Gb/s”，不足以确认能建立雷雳网桥。

KeyBridge reports observed configuration, link and network states. A missing link alone cannot identify a cable’s exact capabilities. See [cable selection and wired diagnosis](docs/setup.md#cable-and-ports--线材与接口) and the [1.1 release notes](docs/releases/v1.1.md).

软件会显示实际读取到的配置、链路与网络状态；只看到“未检测到链路”时，不能直接断言线材不支持。线材及端口依据：[Apple Mac mini (2024) specifications](https://support.apple.com/en-my/121555) · [Apple IP over Thunderbolt guide](https://support.apple.com/en-gb/guide/mac-help/mchld53dd2f5/mac)。

## Experimental wired microphone / 实验性有线麦克风 · 1.5

Enable **Share microphone · Experimental** below the native-gestures option on either Mac. Setup guides connection, receiver-component installation and source permission as needed. Both switches stay off until capture starts and the receiver accepts audio; switching off either end stops sharing.

在任一端勾选「原生多指手势」下方的 **「共享麦克风 · 实验功能」**，缺少连接、组件或权限时按提示补齐；采集和接收均就绪才会勾选成功，两端状态同步。任一端取消即停止共享。


Share one Mac’s microphone with the paired Mac over the **encrypted wired connection**. Audio uses 48 kHz mono PCM in 20 ms frames; frame duration is not an end-to-end latency promise. **Bluetooth audio is not supported.**

- Microphone sharing is **off by default**, with separate enable/mute controls; choosing a keyboard destination does not turn on the microphone or change its destination.
- The source needs microphone permission. The receiving Mac needs an **optional virtual-microphone component**, installed once with administrator approval. the installer reloads only KeyBridge’s virtual microphone automatically, without restarting the Mac or the system audio service.
- Choose **KeyBridge Microphone** in your receiving voice app. KeyBridge does **not** change the system’s default microphone automatically.
- Disconnecting stops capture; reconnecting does not resume it automatically. This feature has **not yet completed physical two-Mac acceptance testing**, and compatibility with every voice app or macOS version is not established.

通过**已配对、加密的有线连接**，把一台 Mac 的麦克风提供给另一台。音频为 48 kHz 单声道 PCM、每帧 20 ms；帧长不是端到端延迟承诺。**蓝牙不支持音频。**

- 麦克风**默认关闭**，勾选开启／取消即停止；更换键盘控制目标不会自动开启麦克风或改变音频去向。
- 来源端需要麦克风权限。接收端需选装**虚拟麦克风组件**，由管理员批准一次安装；安装后会自动局部重新加载键桥虚拟麦克风，无需重启电脑，也不会重启整个系统音频服务。
- 在接收端语音应用中选择 **KeyBridge Microphone**；软件**不会自动修改系统默认麦克风**。
- 断线立即停止采集，重连后需手动开启。功能**尚未完成双机实机验收**，不承诺所有语音应用或系统版本均兼容。

[Microphone setup and limitations / 麦克风安装与限制](docs/microphone.md) · [1.5 release notes / 1.5 发布说明](docs/release-1.5.md)

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
