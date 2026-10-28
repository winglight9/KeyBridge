import Foundation

extension BridgeStore {
    func localizedDetail(_ value: String) -> String {
        guard chinese else { return value }
        let messages = [
            "No Thunderbolt direct link":"未发现有线直连，请连接支持雷雳的 Type-C 线。",
            "Cannot read Thunderbolt network configuration. Retry or copy diagnostics.":"无法读取雷雳网络配置，请重试或复制诊断信息。",
            "Thunderbolt Bridge is not configured. Check System Settings > Network.":"未找到已配置的雷雳网桥，请检查「系统设置 → 网络」。",
            "Thunderbolt Bridge is disabled. Enable it in System Settings > Network.":"雷雳网桥已停用，请在「系统设置 → 网络」中启用。",
            "No Thunderbolt link detected. Check the cable and ports; this alone does not prove the cable is unsupported.":"未检测到雷雳链路，请检查线材和两端接口；仅凭此状态无法判断线材是否不支持。",
            "Thunderbolt link status is unavailable. Check the cable, ports and Thunderbolt Bridge in Network settings.":"无法读取雷雳链路状态，请检查线材、两端接口及网络设置中的雷雳网桥。",
            "Thunderbolt link detected; waiting for a network address. Check TCP/IP on both Macs.":"已检测到雷雳链路，正在等待网络地址；请检查两台 Mac 的 TCP/IP 配置。",
            "Thunderbolt network is ready; looking for the other Mac.":"雷雳网络已就绪，正在发现另一台 Mac…",
            "Thunderbolt network is ready; select the other Mac to connect.":"雷雳网络已就绪，请选择另一台 Mac 连接。",
            "Thunderbolt network is ready, but no other KeyBridge was discovered. Open KeyBridge on the other Mac and check local-network permission.":"雷雳网络已就绪，但尚未发现对方键桥；请打开对方应用，并检查本地网络权限。",
            "Thunderbolt has a network address, but its interface is unavailable to the app. Retry or copy diagnostics.":"雷雳接口已有网络地址，但应用暂时无法使用；请重试或复制诊断信息。",
            "Network discovery was denied by macOS. Check local-network permission and network policies.":"macOS 拒绝了网络发现，请检查本地网络权限及网络策略。",
            "Network access was denied by macOS. Check permissions and network security policies.":"macOS 拒绝了网络访问，请检查权限及网络安全策略。",
            "Input Monitoring permission required":"请在来源 Mac 授予输入监控权限。",
            "Accessibility permission required":"请在目标 Mac 授予辅助功能权限。",
            "Accessibility permission was revoked":"目标 Mac 的辅助功能权限已关闭，输入已停止。",
            "Input Monitoring permission was revoked":"输入监控权限已关闭，输入已停止。",
            "Bluetooth permission required":"请允许蓝牙访问。",
            "Bluetooth is off":"蓝牙已关闭，请打开后重试。",
            "Bluetooth is unsupported":"当前设备不支持此蓝牙连接。",
            "Bluetooth is resetting":"蓝牙正在重新初始化。",
            "Bluetooth is starting":"蓝牙正在启动。",
            "Discovering Bluetooth devices":"正在发现蓝牙设备…",
            "Connecting Bluetooth":"正在连接蓝牙设备…",
            "Bluetooth connection failed":"蓝牙连接失败。",
            "Bluetooth device is unavailable":"蓝牙设备暂不可用。",
            "Direct device is no longer available":"直连设备暂不可用，请重试。",
            "Direct link timed out; input restored locally":"直连超时，键盘和触摸板已恢复本机使用。",
            "Direct link timed out; local input restored":"直连超时，键盘和触摸板已恢复本机使用。",
            "Emergency return to local input":"已紧急恢复本机输入。",
            "Connection timed out":"连接超时，请检查链路后重试。",
            "Pairing confirmation timed out":"配对确认超时，请重新连接。",
            "Retrying connection":"正在重试连接…",
            "Wired link disconnected":"有线连接已断开。",
            "Bluetooth disconnected":"蓝牙连接已断开。",
            "Mac is sleeping":"Mac 已进入睡眠，输入已停止。",
            "No supported keyboard found":"没有发现支持的键盘。",
            "Disconnected":"已断开连接。"
        ]
        if let localized = messages[value] { return localized }
        if value.hasPrefix("Wired network error: ") { return "有线网络错误：" + value.dropFirst("Wired network error: ".count) }
        if value.hasPrefix("Discovering on ") { return "正在有线直连中发现设备…" }
        return value
    }
}
