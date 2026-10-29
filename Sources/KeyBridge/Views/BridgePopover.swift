import SwiftUI

struct BridgePopover: View {
    @ObservedObject var store: BridgeStore
    private var statusColor: Color {
        switch store.phase {
        case .connected: return .green
        case .unstable, .pairing: return .orange
        case .disconnected: return .red
        default: return .secondary
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(nsImage: BrandAssets.appIcon).resizable().interpolation(.high)
                    .frame(width: 38, height: 38).accessibilityLabel(store.appName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.appName).font(.headline)
                    Text(store.text("Keyboard & trackpad", "键盘与触摸板")).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 3)
                HStack(spacing: 5) { Circle().fill(statusColor).frame(width: 6, height: 6); Text(store.status).font(.caption2) }
                    .padding(.horizontal, 8).padding(.vertical, 5).background(statusColor.opacity(0.1), in: Capsule())
            }
            Divider()
            if store.identityLoading { HStack { ProgressView().controlSize(.small); Text(store.text("Loading device identity…", "正在读取设备身份…")).font(.caption) } }
            if store.identityNeedsAuthorization {
                Button(store.text("Retry device identity", "重试读取设备身份")) { store.allowIdentityAccess() }.buttonStyle(.borderedProminent)
            }
            VStack(spacing: 10) {
                devicePicker(label: store.text("Device", "设备"), selection: Binding(get: { store.sourceID }, set: store.chooseSource), source: true)
                devicePicker(label: store.text("Apply to", "应用于"), selection: Binding(get: { store.targetID }, set: store.chooseTarget), source: false)
            }.padding(12).background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))

            if !store.pairingCode.isEmpty {
                pairingCard
            } else if store.phase == .pairing {
                Text(store.text("Waiting for the other Mac to confirm pairing.", "等待另一台 Mac 确认配对。")).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Text(store.text("Connection", "连接方式")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(store.text("Wired preferred", "优先有线")).font(.caption2).foregroundStyle(.blue)
            }
            HStack(spacing: 8) { modeButton(.wired); modeButton(.bluetooth) }
            if let selection = store.confirmMode {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selection == .bluetooth ? store.text("Switch to Bluetooth?", "确认切换到蓝牙？") : store.text("Switch to the wired link?", "确认切换到有线？")).font(.caption).bold()
                    Text(store.text("Forwarding pauses while the selected link connects.", "切换链路时会暂停转发，连接后可重新选择输入目标。")).font(.caption2).foregroundStyle(.secondary)
                    HStack { Spacer(); Button(store.text("Cancel", "取消")) { store.confirmMode = nil }; Button(store.text("Switch", "确认切换")) { store.switchMode() }.buttonStyle(.borderedProminent) }
                }.padding(10).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(store.routeDescription, systemImage: store.forwarding ? "arrow.right" : "keyboard").font(.caption)
                if let latency = store.latency { Text(store.text("Measured round trip: ", "实测链路往返：") + String(format:"%.1f ms", latency)).font(.caption2).foregroundStyle(.secondary) }
                if !store.error.isEmpty { Text(store.localizedDetail(store.error)).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                else if !store.detail.isEmpty, !store.ready { Text(store.localizedDetail(store.detail)).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
            }.frame(maxWidth:.infinity, alignment:.leading).padding(10)
                .background((store.phase == .unstable ? Color.orange : Color.secondary).opacity(0.07), in: RoundedRectangle(cornerRadius: 9))

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 7) {
                    Label(store.microphoneStatus, systemImage:store.microphoneActive ? "mic.fill" : "mic.slash")
                        .font(.caption).foregroundStyle(store.microphoneActive ? Color.orange : Color.secondary)
                    Text(store.text("Wired only · Separate from keyboard sharing. Select KeyBridge Microphone in the receiving app.", "仅有线 · 独立于键盘共享。在接收端应用中选择“KeyBridge Microphone”。"))
                        .font(.caption2).foregroundStyle(.secondary)
                    if !store.microphoneError.isEmpty {
                        Text(store.microphoneError).font(.caption2).foregroundStyle(.red).textSelection(.enabled)
                    }
                    HStack {
                        if store.microphoneActive {
                            Button(store.text("Stop microphone", "停止麦克风")) { store.stopMicrophone() }
                            if store.microphoneState == "sending" {
                                Button(store.text("Mute", "静音")) { store.muteMicrophone() }
                            }
                        } else {
                            Button(store.microphoneState == "muted" ? store.text("Resume microphone", "恢复麦克风") : store.text("Share this microphone", "共享本机麦克风")) { store.startMicrophone() }
                                .disabled(!store.microphoneCanStart)
                        }
                        Menu {
                            Button(store.text("Install receiving component…", "安装接收组件…")) { store.openMicrophoneInstaller() }
                            Button(store.text("Microphone permissions…", "麦克风权限…")) { store.openMicrophonePrivacy() }
                        } label: { Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                    }.font(.caption)
                    if !store.microphoneDriverAvailable {
                        Text(store.text("Receiving component not loaded on this Mac. Install it only if this Mac will receive audio; a restart may be needed.", "本机尚未加载接收组件。接收音频时才需安装，安装后可能需要重启。"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.top, 5)
            } label: {
                HStack {
                    Text(store.text("Microphone · Experimental", "麦克风 · 实验功能")).font(.caption)
                    if store.microphoneActive { Image(systemName:"mic.fill").foregroundStyle(.orange); Text(store.microphoneStatus).font(.caption2).foregroundStyle(.orange).lineLimit(1) }
                }
            }

            HStack(spacing: 7) {
                Button(store.text("Stop forwarding", "停止转发")) { store.stopForwarding() }.buttonStyle(.bordered)
                Button(store.text("Retry", "重试连接")) { store.retry() }.buttonStyle(.borderedProminent)
                if store.mode == .wired, store.phase == .disconnected || store.phase == .unstable {
                    Button(store.text("Bluetooth…", "蓝牙…")) { store.requestMode(.bluetooth) }.buttonStyle(.bordered)
                }
            }.font(.caption)
            Divider()
            Label(store.text("The display mouse stays local and can operate this menu.", "显示器鼠标始终本地可用，可操作此菜单。"), systemImage: "computermouse").font(.caption2).foregroundStyle(.secondary)
            Toggle(store.text("Native multi-finger gestures · Experimental", "原生多指手势 · 实验功能"), isOn: $store.gestureForwardingEnabled)
                .toggleStyle(.switch).font(.caption2)
            Text(store.text("Movement, clicks, dragging and two-finger scrolling are available. Experimental gestures forward native events for the destination to interpret; pinch, rotation and three/four-finger gestures still need device testing. Changing this option pauses forwarding.", "支持移动、点击、拖动和双指滚动。实验手势将原生事件交给目标设备解释；捏合、旋转及三／四指操作仍需实机确认。更改此项会暂停转发。"))
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { store.grantInput() } label: { Label(store.text("Input", "输入监控"), systemImage: store.inputPermission ? "checkmark.circle.fill" : "circle") }
                    .foregroundStyle(store.inputPermission ? Color.green : Color.secondary)
                Button { store.grantReceive() } label: { Label(store.text("Control", "辅助功能"), systemImage: store.receivePermission ? "checkmark.circle.fill" : "circle") }
                    .foregroundStyle(store.receivePermission ? Color.green : Color.secondary)
                Spacer()
                Menu {
                    Button("English") { store.language = "en" }
                    Button("简体中文") { store.language = "zh" }
                    Divider()
                    Button(store.text("Disconnect", "断开连接")) { store.disconnect() }
                    Button(store.text("Copy diagnostics", "复制诊断信息")) { store.copyDiagnostics() }
                    Button(store.text("Forget paired Macs", "清除配对记录")) { store.forgetPairing() }
                    Divider()
                    Button(store.text("Quit KeyBridge", "退出键桥")) { store.quit() }
                } label: { Image(systemName: "gearshape") }.menuStyle(.borderlessButton).fixedSize()
            }.font(.caption2).buttonStyle(.plain)
        }
        .padding(16).frame(width: 388)
    }
    private func devicePicker(label: String, selection: Binding<String>, source: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width:58, alignment:.leading)
            Picker(label, selection: selection) {
                ForEach(store.options) { option in
                    Text(option.name + (option.id == store.local.id ? store.text(" (this Mac)", "（本机）") : ""))
                        .tag(option.id).disabled(source && !option.canSource)
                }
            }.labelsHidden().pickerStyle(.menu).frame(maxWidth:.infinity)
        }
    }
    private func modeButton(_ mode: LinkMode) -> some View {
        Button { store.requestMode(mode) } label: {
            HStack(alignment:.top, spacing: 6) {
                Image(systemName: store.mode == mode ? "largecircle.fill.circle" : "circle").foregroundStyle(store.mode == mode ? Color.accentColor : Color.secondary)
                VStack(alignment:.leading, spacing:3) {
                    Text(mode == .wired ? store.text("Direct cable", "有线直连") : store.text("Bluetooth", "蓝牙")).font(.caption).bold()
                    Text(mode == .wired ? store.text("USB-C · Thunderbolt", "USB-C · 雷雳桥接") : store.text("Device to device", "设备间直连")).font(.system(size:9)).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
            }.frame(maxWidth:.infinity, minHeight:35, alignment:.leading).padding(9)
                .background(store.mode == mode ? Color.accentColor.opacity(0.06) : Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).stroke(store.mode == mode ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.18), lineWidth:1))
        }.buttonStyle(.plain)
    }
    private var pairingCard: some View {
        VStack(alignment:.leading, spacing:8) {
            Text(store.text("Compare this code on both Macs", "比较两台 Mac 上的配对码")).font(.caption).bold()
            Text(store.pairingCode).font(.system(size:27, weight:.semibold, design:.monospaced)).tracking(4).frame(maxWidth:.infinity)
            Text(store.text("Approve on both Macs only if the codes match.", "确认两边配对码相同后，分别点击允许配对。")).font(.caption2).foregroundStyle(.secondary)
            if store.identityChanged { Text(store.text("This Mac's identity changed. Confirm the new code carefully.", "对方设备身份已变化，请重新核对配对码。")).font(.caption2).foregroundStyle(.orange) }
            HStack { Button(store.text("Disconnect", "断开")) { store.disconnect() }; Spacer(); Button(store.localPairApproved ? store.text("Waiting for peer", "等待对方确认") : store.text("Allow pairing", "允许配对")) { store.approvePairing() }.buttonStyle(.borderedProminent).disabled(store.localPairApproved) }
        }.padding(12).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius:10))
    }
}
