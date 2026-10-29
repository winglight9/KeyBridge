# KeyBridge / 键桥 1.2

## 中文

### 新增：实验性有线麦克风共享

- 将一台 Mac 的麦克风，通过已配对、加密的有线连接提供给另一台 Mac。**蓝牙不支持音频。**
- 使用 48 kHz、单声道、16 位小端 PCM，每帧 20 ms（960 个采样）。这是传输格式与帧长，不是实测端到端延迟。
- 独立开启／静音，**默认关闭**；不随「键盘应用于」选择启用或改变音频去向。
- 断线、睡眠或会话结束时停止采集；重连后不会自动恢复录音，需要用户再次开启。
- 接收端选装虚拟麦克风组件，**需要管理员批准一次安装**。系统可能需要用户在方便时重启接收端才能载入组件，不会无提示重启音频服务或电脑。
- 在接收端语音应用内选择 **KeyBridge Microphone**。软件**不会自动修改系统默认麦克风**。

### 验证范围与安装

本轮麦克风功能**尚未完成两台 Mac 的实机音频验收**。不承诺所有语音应用、所有 macOS 版本均能识别或稳定使用，也没有固定延迟、回声消除或系统降噪保证。此前键盘／触摸板验收不能代替音频验收。

两台 Mac 使用相同版本。来源端仅在用户启用后申请麦克风权限；接收端应用也可能需要自己的麦克风权限。组件安装、加载与故障排查见[麦克风说明](https://github.com/winglight9/KeyBridge/blob/main/docs/microphone.md)。当前 Apple Silicon 测试版采用本地签名，**不是 Apple Developer ID 签名，也未经 Apple 公证**。

### 连接提醒

- 蓝牙输入延迟较高，建议临时或备用；**音频仅限有线**。
- 使用明确支持雷雳的认证 Thunderbolt 3 / 4 双 USB-C 线；USB4 需厂商明确兼容雷雳，不能仅凭“全功能”、充电功率或 10 Gb/s 标识判断。
- **Mac mini（2024，M4 / M4 Pro）使用背面雷雳接口**，前面 USB-C 不提供此模式所需的雷雳连接。

## English

### New: experimental wired microphone sharing

- Send one Mac’s microphone to its paired Mac through the encrypted wired connection. **Bluetooth audio is not supported.**
- Audio uses 48 kHz mono signed 16-bit little-endian PCM, in 20 ms frames (960 samples). This describes the wire format and frame duration, not measured end-to-end latency.
- Separate enable/mute controls are **off by default**. Changing the keyboard destination does not enable audio or change its destination.
- Disconnecting, sleeping or ending the session stops capture. Reconnecting does not resume recording; enable it again manually.
- The receiving Mac needs an optional virtual-microphone component with **one-time administrator approval**. macOS may require a user-initiated restart to load it. KeyBridge does not silently restart the audio service or the Mac.
- Choose **KeyBridge Microphone** in the receiving voice app. KeyBridge **does not automatically change the system default microphone**.

### Validation and installation

The microphone feature **has not yet completed physical two-Mac audio acceptance testing**. Recognition and stable operation in every voice app or macOS version are not established. No fixed latency, echo cancellation or system noise-reduction guarantee is made. Earlier keyboard/trackpad acceptance does not validate audio.

Use the same app version on both Macs. The source requests microphone permission only when the user enables sharing; the receiving voice app may need its own microphone permission. See the [microphone guide](https://github.com/winglight9/KeyBridge/blob/main/docs/microphone.md) for component installation, loading and troubleshooting. This Apple Silicon beta is locally signed, **without Apple Developer ID signing or Apple notarization**.

### Connection reminder

- Bluetooth input has higher latency and is best kept for temporary use or backup. **Audio requires wired mode.**
- Choose a certified Thunderbolt 3 / 4 cable with USB-C connectors. USB4 requires explicit manufacturer confirmation of Thunderbolt compatibility; connector shape, charging wattage and a 10 Gb/s label alone are insufficient.
- **Use a rear Thunderbolt port on Mac mini (2024, M4/M4 Pro)**; the front USB-C ports do not provide the Thunderbolt connection this mode needs.
