# KeyBridge / 键桥 1.3

## 中文

- 麦克风入口改为「原生多指手势」下方的同款「共享麦克风 · 实验功能」勾选项，移除折叠面板、独立操作按钮和省略号菜单。
- 勾选后检查有线连接、两端版本、接收组件和来源权限，缺少时按步骤引导；组件加载、权限就绪后自动继续。不会代替用户批准管理员安装、麦克风授权或重启电脑。
- **来源采集已启动、接收端已接受首帧音频后，两端才显示已勾选**；准备中保持未勾选，再次点击可取消。任一端取消勾选都停止共享。
- 可从接收端请求所选来源设备开启麦克风。两端需同时更新到 1.3。麦克风保持默认关闭，断线或重启后需重新勾选。
- 状态表示键桥音频链路就绪，不代表所有通话软件已验收。通话软件仍需选择 KeyBridge Microphone，并保留其自身麦克风权限。不会自动改变系统默认输入设备。
- 音频仅支持有线。推荐认证 Thunderbolt 3/4/5 线；USB4 需明确支持雷雳兼容。Mac mini M4/M4 Pro 使用背面雷雳接口。蓝牙输入延迟相对较高。

本版通过编译及打包检查；完整首次安装、权限引导与语音应用收音仍需用户实机确认。当前为本地签名的 Apple Silicon 版本，未获 Apple 公证。

[麦克风使用说明](https://github.com/winglight9/KeyBridge/blob/main/docs/microphone.md)

## English

- Replaces the microphone panel with a single **Share microphone · Experimental** switch below native gestures on both Macs.
- Checking guides missing wired connection, receiver component and source microphone permission requirements. It continues after readiness is detected, without granting permissions, approving installation or restarting for you.
- Both switches turn on only after source capture starts and the receiver accepts audio. They remain off while preparing; click again to cancel. Switching off either Mac stops sharing.
- The receiving Mac can request the selected source Mac's microphone. Update both Macs to 1.3. Default remains off; reconnecting or restarting does not resume capture.
- Voice apps still need to select KeyBridge Microphone and retain their own microphone permission. No system default-input change. Full installation and voice-app audio acceptance remain pending.
- Wired audio only. Use a certified Thunderbolt 3/4/5 cable and rear Thunderbolt ports on Mac mini M4/M4 Pro. USB4 needs explicit Thunderbolt compatibility. Bluetooth input has comparatively higher latency.

Locally signed Apple Silicon build; not Apple notarized.
