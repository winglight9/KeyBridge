# 键桥 / KeyBridge

**一副键盘，管两台 Mac。**  
一个安静待在菜单栏里的小工具，让你直接用 MacBook 自带的键盘和触摸板操控另一台 Mac（比如 Mac mini）。两台装同一个软件，点一下就能切换；桌上的外接鼠标不受影响，继续留在本机用。

**One keyboard. Two Macs.**  
A lightweight macOS menu bar app that lets you use your MacBook’s built-in keyboard and trackpad to control another Mac. Install the same app on both Macs, pick **Device → Apply to**, and keep your external mouse independent on its own Mac.

**macOS 14+ · Apple Silicon Beta · 简体中文 / English · MIT**

[官网 / Website](https://keybridge.886366.xyz/) · [下载 v1.6 / Download](https://github.com/winglight9/KeyBridge/releases/tag/v1.6) · [安装指南 / Setup](docs/setup.md) · [实现原理 / Architecture](docs/architecture.md) · [安全说明 / Security](SECURITY.md)

---

## 现在能做什么 / What works

| 功能 / Feature | 状态 / Status |
| --- | --- |
| 雷雳有线直连（打字、指针、点击、拖拽、双指顺滑滚动） | **已实测可用**（日常主力推荐，几乎无感延迟） |
| 蓝牙无线连接（打字、指针、点击、拖拽、双指滚动） | **已实测可用**（手边没线时备用，延迟会比插线高） |
| 原生多指手势 & 外接鼠标独立留在本机 | **下述有线组合已实测可用**（实验开关默认关闭，需手动开启） |
| 防止自动锁屏（v1.6 新增） | **可用**（连接时临时保持亮屏，不改系统设置，关闭或退出立即恢复） |
| 有线麦克风共享（实验功能） | **尝鲜阶段**（默认关闭，仅限插线；尚未测完所有语音软件） |
| Touch ID、开机/锁屏前输入、Force Touch 重按 | **不支持** |

> **实测范围说明：** 作者已在 **M1 Pro MacBook → M4 Mac mini（两台均为 macOS 15.8.1）** 的有线连接下长期日常实测通过，涵盖打字、触摸板、原生多指手势与外接鼠标独立使用。其他机型、系统版本及第三方应用的兼容性尚未逐一测完，欢迎提交反馈。
>
> **Physical test scope:** Verified daily over a direct Thunderbolt cable on an **M1 Pro MacBook → M4 Mac mini (both macOS 15.8.1)**, covering typing, trackpad, native multi-finger gestures, and external mouse isolation. Other Mac models, macOS versions, and apps are not exhaustively tested yet.

---

## 三步用起来 / Quick start

1. **两台都装同一个软件**：下载 [KeyBridge v1.6](https://github.com/winglight9/KeyBridge/releases/tag/v1.6)，先拖进「应用程序」再打开，避免系统反复弹窗要权限。
2. **给一次权限**：打字那台给「输入监控 + 辅助功能」，被控制那台给「辅助功能」；弹窗询问本地网络或蓝牙时点允许。
3. **核对 6 位验证码，选谁控谁**：两边确认 6 位数字一致并点同意，在菜单里选好用哪台控哪台即可（两边自动同步，不用重复设）。

想切回本机时，直接用外接鼠标点菜单栏，或者按快捷键 **`Control + Option + Command + Escape`** 一秒切回。

1. Install KeyBridge in `/Applications` on both Macs.
2. Grant **Input Monitoring + Accessibility** on the source Mac, and **Accessibility** on the destination Mac (plus Local Network / Bluetooth when prompted).
3. Pick **Direct cable** or **Bluetooth**, confirm the matching 6-digit pairing code on both screens, then choose **Device → Apply to**. Use your external mouse or **`Control–Option–Command–Escape`** anytime to return locally.

---

## 选什么线 & 插哪个口 / Cable & ports

**日常推荐插雷雳线，手感最接近本机；蓝牙适合临时应急。** 连接方式完全由你手动选择，不会偷偷切到 Wi-Fi。

- **线材选择**：请买明确标明 **Thunderbolt 3 / 4 / 5 认证** 的双头 Type-C 线。如果买 USB4 线，要确认支持两台 Mac 之间的「雷雳网桥」——光写“100W 快充”“全功能”“4K 投屏”的普通线大多不行。
- **Mac mini（2024，M4 / M4 Pro）避坑**：**必须插机身背面的三个雷雳口之一**。前面两个 Type-C 口只是普通 USB 3（10 Gb/s），插上去连不上。

- Use a **certified Thunderbolt 3, 4, or 5 USB-C cable** (or a USB4 cable explicitly confirmed for Mac-to-Mac Thunderbolt networking). Charging wattage or display labels alone are not enough.
- **Mac mini (2024, M4 / M4 Pro):** always use one of the **three rear Thunderbolt ports**. The two front USB-C ports are USB 3 only and cannot establish Thunderbolt Bridge.

更多线材排查见 [setup.md](docs/setup.md#cable-and-ports--线材与接口) 与 [v1.6 发布说明](docs/release-1.6.md)。

---

## 麦克风共享（尝鲜功能 · 仅限插线） / Experimental wired microphone

Mac mini 没接麦克风？在菜单里勾选「共享麦克风」，就能把 MacBook 的麦克风通过加密雷雳线借给另一台 Mac 用（**默认关闭，蓝牙不支持传麦**）。

- 如果缺权限或组件，软件会一步步引导补齐；接收端装一次虚拟麦克风后会自动生效，**不用重启电脑**。
- 在微信、腾讯会议等软件里选择 **`KeyBridge Microphone`** 即可，不会篡改你系统默认的麦克风。
- 哪边关掉开关都会立刻停止收音，断线重连也不会偷偷自动开麦。

详见 [docs/microphone.md](docs/microphone.md)。

---

## 隐私、安全与首次打开提示 / Privacy & first launch

- **全程直连加密，不上云**：按键、触控和可选音频都在已配对的两台 Mac 之间加密直传，不录屏、不经云端服务器。
- **不怕卡键**：拔线、合盖、休眠或断连会立刻释放所有远端按键并交回本机控制权。
- **首次打开被系统拦截**：因为目前是免费开源测试版，没有买 Apple 付费公证，macOS 第一次打开会弹提示。确认来源后，到 **「系统设置 → 隐私与安全性 → 仍要打开」** 放行一次即可，**切勿全局关闭 Gatekeeper**。

---

## 从源码自行构建 / Build from source

需要 macOS 14+、支持 Swift 6 的 Xcode / Command Line Tools 以及 Python 3（零第三方 Swift 依赖）：

```sh
# 仅构建打包，不替换正在运行的应用
KEYBRIDGE_CONFIGURATION=release ./script/build_and_run.sh --build-only

# 构建并启动开发版
./script/build_and_run.sh

# 运行协议与诊断检查
./script/test.sh
```

构建产物位于 `outputs/KeyBridge.app`。支持 `--verify`、`--logs`、`--telemetry`、`--debug` 参数；签名证书可通过环境变量 `KEYBRIDGE_SIGN_IDENTITY` 指定。更多架构与安全边界说明见 [docs/architecture.md](docs/architecture.md) 与 [SECURITY.md](SECURITY.md)。

---

## 反馈 / Feedback

遇到问题欢迎在 [GitHub Issues](https://github.com/winglight9/KeyBridge/issues) 反馈，附带软件版本、两台 Mac 机型与系统版本、连接方式即可。

[MIT License](LICENSE)
