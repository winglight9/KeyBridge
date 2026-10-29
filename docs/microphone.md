# 有线麦克风共享 / Wired microphone sharing · 1.2 experimental

本文记录 1.2 首版方案、安装要求和验收边界；不是功能已安装或已实测可用的声明。

## 在 M1 Pro → Mac mini 上启用

1. 两台 Mac 安装 1.2，并用雷雳有线模式完成连接与配对。把应用放在 `/Applications/KeyBridge.app`；接收组件仅接受这个位置运行的键桥写入。
2. **只在 Mac mini** 打开键桥菜单 →「麦克风 · 实验功能」→ 省略号菜单 →「安装接收组件…」。也可以打开本次发行的 `KeyBridge-Microphone-1.2.pkg`。
3. 在系统安装器中确认安装并验证管理员身份。安装不会自动重启电脑或音频服务；若设备尚未出现，在方便时自行重启 Mac mini。
4. 在 **M1 Pro** 打开「麦克风 · 实验功能」→「共享本机麦克风」，首次使用时允许麦克风访问。采集来源为系统当前默认麦克风；不会自动改变你的输入设备设置。
5. 在 Mac mini 的通话／录音软件中选择 **KeyBridge Microphone**，需要时允许该软件使用麦克风。检查语音软件的输入电平或进行实际通话，才能确认完整链路可用。
6. 来源端「静音」会停止采集；点「恢复麦克风」才重新开启。任一端可「停止麦克风」，有线断开后也需手动重新启用。

若安装后设备没有出现，请先复制诊断信息；安装完成不等于设备已加载。此实验功能的首次加载、实际收音和语音应用兼容性仍待两台 Mac 实测。

## 首版范围

- 一台 Mac 采集其麦克风，经已配对、加密的 有线会话 发送给另一台；接收端通过虚拟音频输入设备提供给语音应用。仅开放有线模式。
- 传输格式为 **48 kHz、单声道、16 位小端 PCM（pcm_s16le）、20 ms 一帧（960 个采样）**。20 ms 是帧长度，不是端到端延迟承诺。
- 麦克风有独立的启用、静音和状态显示，**默认关闭**。明确显示麦克风来源及接收设备；切换「键盘应用于」不改变麦克风去向或录音状态。
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

## macOS 14+ 安装及重新加载

**官方已确认：** Apple 的 AudioServerPlugIn 示例要求把 `.driver` 安装到 `/Library/Audio/Plug-Ins/HAL`，随后**重新启动电脑**，再在「音频 MIDI 设置」中检查设备。[5] 这是有官方依据的加载步骤；Apple 示例没有承诺复制后即刻热加载，也没有把终止 `coreaudiod` 列为该示例的标准安装步骤。

**本项目部署建议：**

1. 只在需要接收音频的 Mac 安装虚拟输入。应用先说明安装位置和用途，用户点击「安装虚拟麦克风」后交给系统安装器验证管理员身份。正常运行／录音不应反复要求管理员密码。
2. 安装包仅写入项目自己的 `.driver` 及必要文件，确认签名、架构、版本、权限和来源；更新时保存可回退副本，失败不留下半份插件。不要直接把管理员密码交给应用、脚本或聊天。
3. 安装后显示 **“虚拟麦克风已安装，请在方便时重新启动 Mac，让系统载入。现在不会重启。”** 可提供「稍后」及显式「重新启动…」入口；先让用户结束会议、保存录音和工作。后台不能自行重启电脑。
4. 系统启动后，通过 Core Audio 设备枚举及「音频 MIDI 设置」确认输入设备出现，才显示「可用」。安装器成功、路径存在或签名检查通过不等于已经加载。
5. 若计划提供「刷新音频服务」，需单独、明确说明 **“会暂时中断这台 Mac 的全部音频，可能影响正在通话和录音的应用”**，取得用户当次确认后才能进行。不能在安装、升级、发现失败或点击普通重连时静默终止／重启 `coreaudiod`。该刷新方式须在目标系统实测，不替代官方重启流程，也不能保证无需重启。

**尚未建立：** macOS 14 各版本、用户当前 macOS 15.8.1 上该具体插件的签名加载策略、首次加载、热刷新、升级和卸载行为均需实际安装验收。本地签名、非 Developer ID、未经公证的应用／插件不可描述成已满足公开分发条件。Apple 的公证文档另有插件分发要求；需要检查具体交付包和系统提示，不能以关闭 SIP、全局 Gatekeeper 或删除安全属性作为默认安装方案。[7]

卸载也只移除本项目插件，并清楚告知需要重新加载音频系统或稍后重启才能完成移除；不要静默重启服务。

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
