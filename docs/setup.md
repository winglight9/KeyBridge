# Setup / 安装与使用

## Install on both Macs / 两台安装

1. Download the ZIP from the [v0.2.0-beta.1 release](https://github.com/winglight9/KeyBridge/releases/tag/v0.2.0-beta.1), unzip it, and move `KeyBridge.app` into **Applications** on both Macs.
2. Open the installed app. It appears in the menu bar; click its icon to show the popover.
3. This beta is locally signed, without an Apple Developer ID or Apple notarization. If macOS blocks it, review the source/release and the exact warning. If you trust this copy and macOS offers it, use **System Settings → Privacy & Security → Open Anyway** for this app, then confirm the app-specific prompt. If the option is absent or the warning reports damage/malware, stop and report the exact warning rather than bypassing it. Do not disable Gatekeeper system-wide or blindly remove quarantine.

两台都将软件放到「应用程序」后再打开。当前为本地签名测试包，未经 Apple 公证。若系统拦截，先确认下载来源及警告内容；信任当前副本且系统提供入口时，可在「系统设置 → 隐私与安全性」点击当前应用的「仍要打开」。没有入口或提示损坏／恶意软件时，请保留原文反馈，不要直接绕过安全检查。

## Permissions / 权限

| Where / 哪台 | Required / 所需权限 |
| --- | --- |
| Input source / 键盘与触摸板来源 | Input Monitoring + Accessibility / 输入监控 + 辅助功能 |
| Input destination / 被控制设备 | Accessibility / 辅助功能 |
| Both, in Bluetooth mode / 蓝牙模式两台 | Bluetooth access when requested / 允许蓝牙访问 |
| Wired discovery / 有线发现 | Local-network access if requested by macOS / 系统询问时允许本地网络访问 |

Click **Input** or **Control** in the popover to open the relevant settings. In **Privacy & Security**, enable the installed `/Applications/KeyBridge.app`. If it is missing, add that copy with the `+` button. Authenticate with macOS when requested. If macOS asks to quit and reopen, do so after saving work. Return to the popover and check its permission indicators. The receiver does not need Input Monitoring merely to receive input.

菜单中的「输入监控」「辅助功能」按钮可打开对应设置。在「隐私与安全性」中启用已安装的键桥；列表没有时，用 `+` 添加「应用程序」内这一份。系统要求身份验证或退出重开时，按提示操作。回到菜单确认权限指示。仅接收输入的一端不必因此开启输入监控。

Replacing the app with a differently signed build can affect permission recognition. Avoid keeping several copies open. KeyBridge allows one instance per user; reopening an existing instance shows its popover. Do not reset the entire privacy database as a routine setup step.

## Choose a route / 选择输入去向

- **Device / 设备:** the Mac whose keyboard and built-in trackpad you want to use.
- **Apply to / 应用于:** the Mac that should receive those inputs.
- Labels use the current local network name. Renaming a Mac does not grant it a new pairing identity.
- First connect: compare the six-digit code on both screens and approve both. A connected link alone does not mean forwarding is active; check the route line.
- Choose the source as its own destination, or click **Stop forwarding / 停止转发**, to keep input local.
- Keep the external display mouse available for menu clicks and monitor input switching. KeyBridge does not switch the monitor’s video input.

## Connection modes / 连接方式

**Bluetooth:** select it on both Macs, allow Bluetooth, and choose the discovered Mac. The app performs its own verification-code pairing. System Bluetooth pairing is not a substitute for approving KeyBridge’s code on both Macs. Mild latency was observed in the user’s M1 Pro/M4 setup; there is no zero-latency promise.

**Direct cable:** connect ports and a cable that support Thunderbolt networking, enable Thunderbolt Bridge in Network settings if necessary, and choose **Direct cable** on both. A USB-C connector alone does not establish Thunderbolt capability. This release’s cable path still needs physical two-Mac acceptance testing.

**Transport choice:** a new install prefers wired; the last manually selected mode is remembered. Switching pauses forwarding and asks for a mouse-clickable confirmation. There is no Wi-Fi fallback, and a failed wired link does not silently become Bluetooth.

### Wired diagnosis / 有线诊断

The app reads network configuration, link state and addresses without changing them. It can report:

| Observed state / 观察状态 | Meaning and next step / 含义及处理 |
| --- | --- |
| Configuration cannot be read / 无法读取网络配置 | Retry and copy diagnostics; this does not establish a cable problem / 重试并复制诊断，不能据此判断线材 |
| Thunderbolt Bridge missing or disabled / 雷雳网桥未配置或停用 | Check Network settings and enable/configure the intended bridge / 检查网络设置中的网桥 |
| No link / 未检测到链路 | Check both ports, seating and the cable; a cable-capability conclusion needs more evidence / 检查两端接口及线材，尚不能直接断言线材不支持 |
| Link status unavailable / 无法读取链路状态 | Inspect ports, cable and bridge settings; diagnostics distinguish unknown from down / 检查接口、线材与网桥，未知不等于已断开 |
| Link up, waiting for address / 链路已建立，等待地址 | Check both Macs’ TCP/IP state / 检查两台 TCP/IP 状态 |
| Network ready, no peer / 网络就绪，未发现对方 | Open KeyBridge on the other Mac, select wired and check any local-network permission / 检查对方软件、模式和本地网络权限 |
| Access denied / 网络访问被拒绝 | Check the reported permission/policy; do not assume a bad cable / 检查权限或网络策略，不能据此判断线材 |

A missing link cannot reliably distinguish an unplugged cable, unsuitable cable, port issue or unavailable peer. The app reports that uncertainty instead of inventing a specific cable diagnosis. Wired discovery and input are confined to the configured Thunderbolt Bridge; ordinary Wi-Fi/LAN discovery is not used as fallback.

## Native gestures / 原生手势

Pointer movement, clicks, dragging and two-finger scrolling have been user verified over Bluetooth. **Native multi-finger gestures · Experimental** is a separate source-side option, **off by default**. Enable it on the input-source Mac when you are ready to perform a physical test. Changing it pauses forwarding; choose the destination again to resume.

移动、点击、拖动和双指滚动已有蓝牙实测。「原生多指手势 · 实验功能」默认关闭；准备实测时，在输入来源 Mac 开启。更改此项会暂停转发，再次选择目标后恢复。

The experimental path transports native gesture events through the same authenticated link and lets the target system/app interpret them. It does not map gestures to hardcoded shortcuts. Pinch, rotation and three/four-finger behavior—including four-finger upward swipes—has **not yet been confirmed on physical devices**. Some native or system gestures may be rejected or behave differently on the destination. Remote-control tools can inject different event types, so a gesture working through another remote app does not prove this path works.

## Stop, reconnect and report / 停止、重连与反馈

Use **Stop forwarding**, **Retry**, **Disconnect** or the mode controls with your external mouse. **Control–Option–Command–Escape** is an additional emergency return. Connection stalls, sleep and capture failures stop interception and release remote pressed keys/buttons. Retry reconnects the saved device and leaves forwarding explicit.

The gear menu’s **Copy diagnostics** provides permissions, route state, connection information and counters. Review/redact device names and local network details before posting. Never share `device-identity.key`, passwords, signing material or deployment credentials. The runtime status file is `~/Library/Application Support/KeyBridge/status.json`; it is not a keystroke log.
