# 有线麦克风共享 / Wired microphone sharing · 1.5 experimental

本文记录 1.5 的安装、局部重新加载与验收边界；区分已确认的组件／传输状态与仍待确认的语音应用效果。

## 在 M1 Pro → Mac mini 上启用

两台 Mac 都更新到 1.5，将应用放在 `/Applications/KeyBridge.app`。在「设备」选择 M1 Pro；麦克风方向与此来源一致，接收到已配对的另一台 Mac，与键盘的「应用于」目标独立。

1. 在任一台 Mac 的键桥菜单中，找到「原生多指手势」下方的 **「共享麦克风 · 实验功能」**，点击勾选。
2. 软件检查有线连接、两端版本、接收组件和来源麦克风权限。未就绪时保持不勾选，只在需要时显示安装／授权提示；完成后自动继续准备。
3. 缺少接收组件时，在接收端确认系统安装器并验证管理员身份。安装器会自动局部重新加载键桥虚拟麦克风，并继续准备；无需重启电脑。重连不会自动恢复录音。
4. 来源端需要麦克风授权时，按系统提示允许；已经拒绝过时会提供设置入口，检测到允许后继续。
5. **来源采集成功且接收端实际接受首帧音频后，两端才显示已勾选。** 任一端取消勾选会停止双方共享。准备中再次点击可取消。

接收端通话／录音软件仍需选择 **KeyBridge Microphone**，并保留该应用自身的麦克风权限；键桥不会替第三方应用授权，也不会自动改变系统默认输入设备。采集来源为系统当前默认麦克风。

此状态表示键桥采集和虚拟设备接收链路就绪，不能代替通话软件的实际收音验收。

## 首版范围

- 一台 Mac 采集其麦克风，经已配对、加密的 有线会话 发送给另一台；接收端通过虚拟音频输入设备提供给语音应用。仅开放有线模式。
- 传输格式为 **48 kHz、单声道、16 位小端 PCM（pcm_s16le）、20 ms 一帧（960 个采样）**。20 ms 是帧长度，不是端到端延迟承诺。
- 麦克风有独立的勾选项和状态显示，**默认关闭**。明确显示麦克风来源及接收设备；切换「键盘应用于」不改变麦克风去向或录音状态。
- 用户点击启用后才申请采集授权；授权成功、接收端虚拟设备可用且有线会话完成认证后才开始采集。不能因应用启动、键盘连接或权限已授权而自动录音。
- 静音停止本端采集并清空待发音频；接收端输出静音。解除静音由用户明确操作。
- 断线、睡眠、会话认证失效、对端退出或采集故障时，停止采集、清空音频队列并使虚拟输入静音。重连后保持关闭，提示用户再次启用，**不自动恢复录音**。
- 不承诺蓝牙音频、所有会议／语音软件识别、回声消除、系统降噪或固定延迟。首版无需改动全系统默认输入设备；用户在目标应用中选择键桥麦克风。

## 采集与授权

Apple 的 `AVAudioEngine.inputNode` 支持连接下游节点或安装录音 tap 获取输入。[1] 先读取实际硬件格式，再按需要转换为线上的 48 kHz 单声道格式；不要假定所有麦克风的原生采样率和声道相同。音频回调仅搬运有界缓冲，转换／封包／加密发送不要阻塞实时回调；队列满时丢弃过期音频，不能积压为越来越长的延迟。

来源应用必须有 `NSMicrophoneUsageDescription`，并在开始采集前检查 `AVCaptureDevice.authorizationStatus(for: .audio)`；未询问时调用 `requestAccess(for: .audio)`。[2][3] 拒绝或受限时保持关闭，显示实际原因及设置入口。已开启输入监控／辅助功能不代表已获得麦克风权限。若启用 Hardened Runtime／App Sandbox，需按实际签名配置加入对应音频输入资源权限并验证；不能把权限键代替用户授权。[4]

推荐短文案：

- 首次使用：**“将这台 Mac 的麦克风发送到已配对的另一台 Mac。仅在你开启时采集。”**
- 未授权：**“请允许键桥使用麦克风。可在「系统设置 → 隐私与安全性 → 麦克风」中开启。”**
- 已断开：**“有线连接已断开，麦克风已停止。重连后请手动开启。”**
- 接收设备未就绪：**“请先在接收端安装键桥麦克风，再手动开启。”**

接收端语音应用通常也需要用户允许其访问麦克风。键桥不能替第三方应用批准授权；选择虚拟设备后无声音，应分别确认来源采集状态、接收缓冲状态、虚拟设备是否出现、语音应用的设备选择及其权限。

## 为什么需要接收端虚拟设备

仅把 PCM 送入接收端应用内存，不会自动成为其他应用可选择的麦克风。建议实现 **AudioServerPlugIn 虚拟输入**；Apple 的虚拟设备示例就是 Audio Server Driver Plug-in，并将该方式作为虚拟设备的推荐方案。[5][6] 这里不需要为了虚拟麦克风引入 DriverKit 的硬件驱动扩展及其单独授权体系。

接收进程把已验证的 PCM 写入有界共享缓冲，HAL 插件按音频时钟读取并提供输入。插件无数据、会话结束或缓冲欠载时返回零；不重放断线前音频。不让 HAL 实时线程等待网络、执行加密、写日志、等待锁或分配无界内存。应约束共享缓冲的大小、格式和读写权限，不能接受任意本地进程提供的未经验证数据。

## 安装与局部重新加载

仅在接收端安装 `/Library/Audio/Plug-Ins/HAL/KeyBridgeMicrophone.driver`，由系统安装器验证管理员身份。安装完成后，postinstall 只查找 `_coreaudiod` 账户下、进程名严格等于 **Core Audio Driver (KeyBridgeMicrophone.driver)** 的宿主，再次核对 PID、UID 与进程名后重新加载它。不会终止主 `coreaudiod`、其他音频驱动或重启电脑。

已在目标 Mac mini（macOS 15.8.1）实机确认局部重新加载：旧宿主 PID 337 → 新宿主 4078，设备恢复且实际加载版本变为 1.4 / implementationVersion 2；主 `coreaudiod` 仍为 PID 193，其他音频组件 PID 保持不变。这个记录验证组件重新加载，不等于已经完成实际收音验收。

安装器更新期间仅键桥的虚拟麦克风可能短暂消失／中断。若此前正在共享，应停止采集；网络断开后仍需用户重新开启。首次安装或更新发生在显式勾选的准备过程中，只有组件、授权和音频接收均就绪，才显示勾选成功。

在「音频 MIDI 设置」或诊断信息中确认设备实际出现与加载版本，不能只以安装成功为准。其他 macOS 版本的宿主隔离／恢复行为仍待验证；加载失败应复制诊断排查，不把重启电脑作为默认处理步骤。当前版本仍为本地签名，非 Apple Developer ID，未经公证。[7]

卸载仅移除本项目组件，并局部重新加载其宿主以移除设备；不静默终止整个系统音频服务。

## 发布前验收边界

尚须分别确认：来源权限允许／拒绝、实际采样格式转换、双端认证、有线音频连续性、静音无采集、拔线停止与不自动恢复、HAL 欠载输出静音、睡眠唤醒、无管理员日常运行，以及用户要用的具体语音应用能否列出和使用虚拟麦克风。应记录设备、系统、应用版本及实测延迟；键盘或触摸板已通过验收不能作为音频验收证据。

## Apple 官方资料

1. [AVAudioEngine.inputNode](https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode)
2. [Requesting Authorization for Media Capture on macOS](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)
3. [NSMicrophoneUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription)
4. [App Sandbox entitlement reference: microphone access](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
5. [Creating an Audio Server Driver Plug-in](https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in)
6. [Creating an audio device driver](https://developer.apple.com/documentation/audiodriverkit/creating-an-audio-device-driver)
7. [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## 1.4 接收组件更新

旧组件在 macOS 15.8.1 的系统音频账户下使用 `PROC_PIDTBSDINFO` 查询另一用户的键桥进程，会返回 `EPERM`，导致首次握手返回 Core Audio `nope`（1852797029）。在 Mac mini 上以相同音频账户执行的诊断确认了该查询失败；改用内核公开的 `KERN_PROC_PID` 查询后，用户身份、路径及完整代码签名校验全部通过。

1.4 保留控制台用户、固定应用路径、签名及 PID 启动时间校验，并补充驱动版本、失败步骤与原始错误码。若检测到已加载的旧组件，勾选共享时会引导更新接收组件；更新文件不等于音频服务已加载新组件；1.5 起安装器自动局部重新加载本组件，无需重启接收端。

此修复已验证账户环境下的身份校验兼容性；更新组件加载后的完整握手和实际语音应用收音仍须确认。

## 音频传输实机记录

2026-10-30，在局部重新加载 1.4 接收组件后，Mac mini 诊断显示 `authenticationStage: 0`、`authenticationCode: 0`、`receiving: true`，并已接收 6,208 帧音频。该记录确认来源采集、加密链路和虚拟设备接收，不等于已经确认每款通话软件的实际听感或延迟。
