# KeyBridge / 键桥 1.4

## 中文

### 修复麦克风组件拒绝连接

- 修复在 Mac mini、macOS 15.8.1 上复现的进程校验兼容问题：音频服务账户执行 `PROC_PIDTBSDINFO` 跨用户查询返回 `EPERM`，使虚拟麦克风首次连接被拒绝，显示 `1852797029 / nope`。
- 改用内核公开的 `KERN_PROC_PID` 查询身份及启动时间。保留控制台用户、固定应用路径、代码签名和 PID 重用检查；没有取消身份校验。
- 在 Mini 音频账户下，新查询方式及后续完整签名校验已通过诊断；安装后驱动内部的实际握手和语音收音仍待验收。
- 增加驱动实际加载版本、认证失败步骤、错误码和调用进程信息，后续可从复制诊断中定位。
- 勾选「共享麦克风」时会识别旧组件并引导更新。**已安装旧组件的接收端也需要更新组件，并在方便时重启，让音频服务加载新版本。仅更新键桥应用不够。**不会自动重启电脑或音频服务。

麦克风仍为默认关闭的有线实验功能；来源采集成功且接收端接受音频后，两端才显示开启。取消任一端即可停止。通话软件仍需选择 KeyBridge Microphone。采用本地签名，未获 Apple 公证。

推荐认证 Thunderbolt 3/4/5 线；USB4 需明确雷雳兼容。Mac mini M4/M4 Pro 使用背面雷雳接口。蓝牙输入延迟相对较高，音频不支持蓝牙。

## English

- Fixes a reproduced identity-query compatibility failure under the macOS 15.8.1 audio-service account: cross-user `PROC_PIDTBSDINFO` returns `EPERM`, causing microphone connection rejection (`1852797029`, `nope`).
- Uses the kernel's public `KERN_PROC_PID` query while retaining console-user, installed-app path, code signature and process start-time checks.
- The updated query and subsequent full signature validation passed under the audio account on the Mini. Actual loaded-driver handshake and voice-app audio acceptance remain pending.
- Diagnostics now include loaded implementation version and the last authentication stage, error and caller PID.
- Enabling the microphone guides receiving-component updates. Receivers with an old component must update it and restart when convenient to load it; updating the app alone is insufficient. No automatic audio-service or Mac restart.

Wired microphone sharing remains experimental and off by default. Both switches indicate enabled only after capture and reception are ready. Select KeyBridge Microphone in your voice app. Locally signed, not Apple notarized.
