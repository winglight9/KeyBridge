# KeyBridge / 键桥 1.5

- 接收组件安装／更新后，自动局部重新加载键桥的虚拟麦克风，取消默认要求重启电脑的流程。
- 不终止整个系统音频服务或其他音频驱动。管理员确认仍由系统安装器处理；键桥虚拟麦克风可能短暂中断。
- 已在 Mac mini、macOS 15.8.1 上确认：键桥驱动宿主更换，主 coreaudiod 与其他音频组件 PID 不变，新驱动实际加载。组件恢复不等于语音应用已完成收音验收。
- 修复 Fn 接收事件类型遗漏，增加 Fn／扩展功能键／系统按键的原生事件通道，保留按下、松开和长按的原始事件类型与标志，不映射成应用快捷键。两端需更新；F5 听写和微信 Fn 长按的实际行为仍待用户确认。
- 保留单个麦克风勾选项：缺少组件时引导安装，准备完成后自动继续，采集与接收都就绪才显示开启。
- 已正常加载 1.4 接收组件的用户无需再次安装组件；应用更新即可。默认关闭、有线限定、断线停止及不自动恢复录音保持不变。

## English

- Receiver installation/update reloads only KeyBridge's isolated virtual-microphone helper; no computer restart is requested.
- The installer does not terminate coreaudiod or other audio drivers. Administrator approval stays in the system installer, and KeyBridge's virtual input may briefly disappear.
- Scoped reload was observed on the target Mac mini with macOS 15.8.1: KeyBridge helper replaced, other audio PIDs unchanged, new component loaded. Voice-app audio acceptance remains separate.
- Adds a negotiated native-keyboard path for Fn, extended function keys and system-defined auxiliary keys, preserving original event types and flags rather than mapping application actions. Physical F5/WeChat acceptance is pending.
- Setup continues automatically after component readiness. Both microphone switches turn on only after capture and reception are ready.
- An already loaded 1.4 receiver implementation is compatible; reinstalling that component is unnecessary. Wired audio only, default off, no automatic capture after reconnect.

当前 Apple Silicon 版本采用本地签名，未经 Apple 公证。推荐认证雷雳线，Mac mini M4/M4 Pro 使用背面雷雳接口；蓝牙输入延迟相对较高，音频不支持蓝牙。
