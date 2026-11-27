'use strict';

const translations = {
  brandName: '键桥 KeyBridge',
  navFeatures: '功能',
  navConnections: '怎么连',
  navMic: '传麦克风',
  navSetup: '怎么装',
  navFaq: '常见问题',
  navDownload: '下载',
  heroBadge: 'macOS 14+ · Apple Silicon 测试版 · 免费开源',
  headline: '一副键盘，<br>管两台 Mac。',
  intro: '直接用 MacBook 自带的键盘和触摸板去操控另一台 Mac，在菜单栏点一下就能切。<br>你桌上的外接鼠标不受影响，继续留在本机用。',
  download: '下载 v1.6',
  viewGithub: '去 GitHub 看看',
  recommendedTag: '日常首选',
  connectionPriority: '插一根雷雳线几乎零延迟 · 手边没线也能用蓝牙顶上',
  previewNote: '点点看 · 试着切换设备、连接方式和开关',
  sendPulse: '试打一下字',
  sourceBadge: '键盘来源',
  targetBadge: '正在被控制',
  builtIn: '自带键盘与触摸板',
  yourOtherMac: '另一台 Mac',
  appName: '键桥',
  statusWired: '有线直连',
  device: '用这台',
  applyTo: '控制它',
  wired: '有线直连',
  bluetoothLabel: '蓝牙',
  toggleLock: '防止自动锁屏',
  toggleMic: '共享麦克风',
  expShort: '尝鲜',
  hintWired: '雷雳线直连中 · 这会儿不会自动熄屏锁屏',

  featuresEyebrow: '桌上有两台 Mac，其实一副键鼠就够了',
  featureHeading: '点一下，接着打字。',
  featureIntro: '桌面上不用摆两把键盘，也不用开远程桌面投屏。安静待在菜单栏里，想控哪台点一下就行。',
  featureOneTitle: '打字和触摸板，跟平时一模一样。',
  featureOneBody: '继续用你最顺手的 MacBook 键盘，顶部功能键、移动、点击、拖拽、双指顺滑滚动（方向和你平时习惯一致）全都能用。打开实验开关后，三指四指等原生多指手势也能直接给另一台 Mac 识别，不是拿快捷键硬凑的。',
  chipScroll: '双指顺滑滚动',
  chipFn: '顶部功能键',
  chipGestures: '原生多指手势（尝鲜）',
  featureTwoTitle: '外接鼠标，永远不会被抢走。',
  featureTwoBody: '插在显示器或本机上的外接鼠标始终归本机自己用，绝不接管。随时用鼠标点菜单栏就能切回本机、重连或停用；键盘也留了一键急救快捷键，怎么都不怕卡住。',
  emergencyLabel: '一键切回本机',
  newIn16: '1.6 新增',
  featureLockTitle: '干活一半，MacBook 不会自动锁屏。',
  featureLockBody: '开启「防止自动锁屏」后，只要两台 Mac 连着，键桥就会临时帮你的 MacBook 保持亮屏，不会因为久没碰它自己锁掉。不改系统设置，关掉开关或退出软件立刻恢复正常。',
  featureThreeTitle: '两台直连加密，不经过任何云端。',
  featureThreeBody: '两台电脑装同一个小软件，核对一下两边显示的 6 位验证码就能配对。所有按键和触控数据加密直传，不用注册账号、没有中转服务器，也不会偷偷切到 Wi-Fi。',
  featureRecoveryTitle: '拔线、合盖立刻松手，不怕卡键。',
  featureRecoveryBody: '一旦拔线、合盖、休眠或连接断开，键桥会马上释放所有按键并把控制权交回本机。如果只是偶尔抖动一下，它会先安全暂停，恢复后自动连回去，不用重新设置。',
  testedNote: '实测说明：作者已在 M1 Pro MacBook + Mac mini M4（两台均为 macOS 15.8.1）的有线直连下长期日常实测通过（含原生多指手势与外置鼠标独立）。其他机型和系统版本尚未逐一测完，欢迎去 GitHub 反馈。',

  connEyebrow: '两种连接方式',
  connectionHeading: '日常插线，救急用蓝牙。',
  connectionIntro: '用有线还是用蓝牙完全由你手动决定，软件不会背着你乱切，也不走 Wi-Fi。',
  tbTitle: '雷雳有线直连',
  thunderboltSub: '日常主力推荐 · 跟手无感延迟',
  bestChoice: '推荐主力',
  thunderboltBody: '拿一根明确标明 Thunderbolt 3 / 4 / 5 认证的双头 Type-C 线，把两台 Mac 直接连起来就行。买 USB4 线的话，记得问清楚客服是否支持两台 Mac 之间的「雷雳网桥」——光写“100W快充”“全功能”“4K投屏”的线不一定能用。',
  tbSpec1: '打字和摸触摸板几乎感觉不到延迟，体验最接近本机',
  tbSpec2: '支持开启原生多指手势（实验功能）',
  tbSpec3: '支持把 MacBook 麦克风共享过去（实验功能）',
  bluetoothSub: '不用插线 · 临时顶一下',
  wirelessBackup: '无线备用',
  bluetoothBody: '手边正好没带雷雳线时，可以用蓝牙先连着。蓝牙移动鼠标指针会有肉眼可见的延迟，平时当备用方案更合适。',
  btSpec1: '打字、移动、点击、拖拽、双指滚动都能用',
  btSpec2: '延迟比插雷雳线明显高一些',
  btSpec3: '蓝牙模式下不支持传麦克风声音',

  portEyebrow: '避坑提示 · MAC MINI (2024)',
  portTitle: 'Mac mini M4 / M4 Pro 一定要插机身背面！',
  portDesc: '新款 Mac mini 机身正面的两个 Type-C 口只是普通 USB 3 接口，长得一模一样，但不能用来建雷雳直连。请把线插到机身背面的三个雷雳口里任意一个。',
  portFront: '机身正面（普通 USB 3）',
  portNo: '✕ 插这里连不上雷雳',
  portRear: '机身背面（雷雳 4 / 雷雳 5）',
  portYes: '✓ 插这三个口任意一个',

  micEyebrow: '尝鲜功能 · 仅限插线',
  microphoneHeading: 'Mac mini 没麦？直接借 MacBook 的用。',
  microphoneIntro: '通过加密的雷雳线把一台 Mac 的麦克风借给另一台。默认关闭，要开语音时点一下开关就行。',
  microphoneBody: '在菜单里勾选「共享麦克风」后，如果还缺权限或组件，软件会一步步提示你补齐。两边都准备好了开关才会真正亮起；哪边点关闭都会立刻停掉收音。',
  micPoint1: '只走加密的雷雳有线直连，声音清晰、低延迟（蓝牙不支持传麦）',
  micPoint2: '接收端装一次虚拟麦克风组件就能马上用，不用重启电脑',
  micPoint3: '在微信、腾讯会议等软件里选「KeyBridge Microphone」就行，不改你系统默认设置',
  microphoneLimits: '提前说明：麦克风共享目前还在尝鲜阶段，没测完市面上所有语音软件；断线重连后不会偷偷自动开麦，放心。',
  microphoneGuide: '查看麦克风详细说明与注意事项',
  sigSourceTitle: 'MacBook 麦克风',
  sigSourceSub: '48 kHz 清晰单声道采集',
  sigPipe: '加密雷雳线直传',
  sigTargetSub: '通话软件直接选用 · 免重启',

  setupEyebrow: '三步上手',
  setupHeading: '几分钟就能用起来。',
  setupIntro: '两台 Mac 装同一个软件、给一次权限、对一下 6 位验证码就搞定。',
  stepOneTitle: '两台都装上同一个软件',
  stepOneBody: '下载键桥 v1.6，先拖进「应用程序」文件夹再打开（这样系统不会反复弹权限）。目前支持 macOS 14 及以上的 Apple Silicon（M 系列芯片）Mac。',
  stepTwoTitle: '给一下系统权限',
  stepTwoBody: '打字那台给「输入监控」和「辅助功能」权限；被控制那台给「辅助功能」权限。弹窗问本地网络或蓝牙时点允许即可。',
  permInput: '输入监控',
  permAccess: '辅助功能',
  stepThreeTitle: '核对验证码，选谁控谁',
  stepThreeBody: '确认两台屏幕上显示的 6 位数字一样，各自点同意。然后在菜单里选好用哪台控哪台，两边会自动同步，不用各设一遍。',
  permPair: '双端核对 6 位验证码',
  betaTitle: '第一次打开被系统拦住了？正常现象',
  betaNote: '因为这是免费的开源测试版，还没花钱买 Apple 开发者公证，macOS 第一次打开会弹警告。确认无误后，去「系统设置 → 隐私与安全性」拉到底点「仍要打开」就行，千万别把整个系统保护关掉。',
  fullInstructions: '看详细图文安装步骤',

  faqHeading: '你可能想问的。',
  faqLead: '关于买什么线、插哪个口、手势支持、隐私安全，一次说明白。',
  faqIssues: '遇到问题？去 GitHub 提一下',
  faqCableQ: '随便拿根 Type-C 线能用吗？',
  faqCableA: '不行。平时充手机、连显示器的普通 Type-C 线大多建不了雷雳直连。请买明确写着 Thunderbolt 3 / 4 / 5 认证的双头 Type-C 线（或确认支持 Mac 间雷雳网桥的 USB4 线），插在两台 Mac 的雷雳口上。',
  faqPortQ: 'Mac mini 应该插前面还是后面？',
  faqPortA: '新款 Mac mini M4 / M4 Pro 必须插机身背面的三个雷雳口之一。前面那两个 Type-C 口只是普通 USB 3，插上去连不上。',
  faqGestureQ: '触摸板能用三指、四指手势吗？',
  faqGestureA: '移动、点击、拖拽和双指顺滑滚动装好就能用。三指四指等原生多指手势属于实验功能，需要在菜单里手动勾开（作者在 M1 Pro → Mac mini M4 / macOS 15.8.1 有线连接下实测可用）。它把原生手势直接交给另一台 Mac 识别，不是拿快捷键硬模拟的。',
  faqLockQ: '用 MacBook 控另一台 Mac 时，MacBook 自己锁屏了怎么办？',
  faqLockA: '把菜单里的「防止自动锁屏」打开就行。两台连着的时候，键桥会临时帮它保持亮屏不锁；关掉开关或退出软件立刻恢复。它不会改你的系统锁屏设置，手动锁屏和合盖也照常有效。',
  faqWifiQ: '会走 Wi-Fi 吗？',
  faqWifiA: '不会。只走你选的雷雳线或蓝牙，绝不偷偷切到 Wi-Fi。',
  faqMouseQ: '想切回本机，用鼠标点就行吗？',
  faqMouseA: '可以！外接鼠标永远归本机自己用，随时点顶部菜单栏就能切回本机或停止共享。键盘上按 Control–Option–Command–Escape 也能一秒切回。',
  faqInstallQ: '为什么首次打开提示“无法验证开发者”？',
  faqInstallA: '因为目前是免费开源测试版，没有买 Apple 付费公证，macOS 默认会拦一下。去「系统设置 → 隐私与安全性 → 仍要打开」放行一次就好，以后打开都不会再拦。',
  faqPrivacyQ: '打字内容安全吗？会上传到云端吗？',
  faqPrivacyA: '完全不上云。按键、触摸板和可选的麦克风音频全部加密后在两台 Mac 之间直传，不录屏、不中转，诊断日志里也不会记录你打过的任何字。',

  ctaHeading: '桌上有两台 Mac？现在就试试。',
  ctaBody: '免费、开源、原生 Swift 打造，支持 macOS 14+ 与 Apple Silicon。',
  releaseNotes: '看看 1.6 更新了啥',
  chineseName: '/ 键桥',
  releases: '历史版本',
  architecture: '实现原理',
  security: '安全说明'
};

const nodes = [...document.querySelectorAll('[data-i18n]')];
const english = new Map(nodes.map((node) => [node, node.innerHTML]));
let language = document.documentElement.lang.startsWith('zh') ? 'zh' : 'en';
let mode = 'wired';

const stage = document.getElementById('product-stage');
const sourceSelect = document.getElementById('source');
const destSelect = document.getElementById('destination');
const wiredBtn = document.getElementById('wired');
const btBtn = document.getElementById('bluetooth');
const lockToggle = document.getElementById('toggle-lock');
const micToggle = document.getElementById('toggle-mic');
const micToggleRow = document.getElementById('mic-toggle-row');
const demoRoute = document.getElementById('demo-route');
const demoStatus = document.getElementById('demo-status');
const demoHint = document.getElementById('demo-hint');
const macbookBadge = document.getElementById('macbook-badge');
const miniBadge = document.getElementById('mini-badge');
const sendPulseBtn = document.getElementById('send-pulse');
const metaDescription = document.getElementById('meta-description');

const metaDescByLang = {
  en: 'KeyBridge (键桥) is a free, open-source macOS menu bar app. Use your MacBook’s keyboard and trackpad to control another Mac over a Thunderbolt cable or Bluetooth, while your external mouse stays on its own Mac.',
  zh: '键桥（KeyBridge）是一款免费开源的 macOS 菜单栏小工具，让你直接用 MacBook 的键盘、触摸板（和麦克风）通过雷雳线或蓝牙操控另一台 Mac，外接鼠标继续留在本机用。'
};

function setLanguage(value) {
  language = value;
  document.documentElement.lang = value === 'zh' ? 'zh-CN' : 'en';
  nodes.forEach((node) => {
    const key = node.dataset.i18n;
    node.innerHTML = value === 'zh' ? (translations[key] || english.get(node)) : english.get(node);
  });

  const langBtn = document.getElementById('language');
  langBtn.textContent = value === 'zh' ? 'EN' : '中文';
  langBtn.setAttribute('aria-label', value === 'zh' ? 'Switch to English' : '切换到中文');
  document.title = value === 'zh' ? '键桥 KeyBridge — 一副键盘，管两台 Mac。' : 'KeyBridge — One keyboard. Two Macs.';
  if (metaDescription) {
    metaDescription.setAttribute('content', metaDescByLang[value]);
  }

  try {
    localStorage.setItem('keybridge-language', value);
  } catch (e) {}

  updatePreview();
}

function updatePreview() {
  const src = sourceSelect.value;
  const dst = destSelect.value;
  const names = { macbook: 'MacBook Pro', mini: 'Mac mini' };
  const isLocal = src === dst;
  const isBt = mode === 'bluetooth';
  const isReverse = src === 'mini' && dst === 'macbook';

  if (isBt || isLocal) {
    micToggle.checked = false;
  }
  micToggle.disabled = isBt || isLocal;
  micToggleRow.classList.toggle('is-disabled', isBt || isLocal);

  const micActive = micToggle.checked && !isBt && !isLocal;
  const lockActive = lockToggle.checked && !isLocal;

  stage.classList.toggle('is-bluetooth', isBt);
  stage.classList.toggle('is-local', isLocal);
  stage.classList.toggle('is-reverse', isReverse);
  stage.classList.toggle('is-mic', micActive);

  if (isLocal) {
    demoRoute.textContent = language === 'zh' ? '仅控制本机 · 已暂停' : 'Local Mac only · paused';
    demoStatus.textContent = language === 'zh' ? '本机' : 'Local';
    macbookBadge.textContent = language === 'zh' ? '各用各的' : 'Local only';
    miniBadge.textContent = language === 'zh' ? '各用各的' : 'Local only';
    demoHint.textContent = language === 'zh'
      ? '现在只控制本机 · 选另一台 Mac 就能接着控'
      : 'Typing on this Mac only · pick another Mac to bridge';
    return;
  }

  demoRoute.textContent = `${names[src]} → ${names[dst]}`;
  demoStatus.textContent = isBt
    ? (language === 'zh' ? '蓝牙' : 'Bluetooth')
    : (language === 'zh' ? '有线直连' : 'Wired');

  if (src === 'macbook') {
    macbookBadge.textContent = language === 'zh' ? '键盘来源' : 'Sending input';
    miniBadge.textContent = language === 'zh' ? '正在被控制' : 'Being controlled';
  } else {
    macbookBadge.textContent = language === 'zh' ? '正在被控制' : 'Being controlled';
    miniBadge.textContent = language === 'zh' ? '键盘来源' : 'Sending input';
  }

  if (isBt) {
    demoHint.textContent = lockActive
      ? (language === 'zh' ? '蓝牙备用连接中 · 不会自动锁屏（传麦需要插线）' : 'Bluetooth backup · screen stays awake (mic needs cable)')
      : (language === 'zh' ? '蓝牙备用连接中 · 延迟会比插线略高（传麦需要插线）' : 'Bluetooth backup · slightly higher delay (mic needs cable)');
  } else if (micActive) {
    demoHint.textContent = language === 'zh'
      ? '雷雳线直连中 · 键盘、触摸板和麦克风都在加密传输'
      : 'Thunderbolt active · keyboard, trackpad & mic streaming';
  } else {
    demoHint.textContent = lockActive
      ? (language === 'zh' ? '雷雳线直连中 · 这会儿不会自动熄屏锁屏' : 'Connected over Thunderbolt · screen stays awake')
      : (language === 'zh' ? '雷雳线直连中 · 低延迟，支持多指手势与传麦' : 'Connected over Thunderbolt · low latency & mic ready');
  }
}

let pulseTimer = null;
function triggerPulse() {
  if (stage.classList.contains('is-local')) {
    destSelect.value = sourceSelect.value === 'macbook' ? 'mini' : 'macbook';
    updatePreview();
  }
  stage.classList.remove('is-pulsing');
  void stage.offsetWidth;
  stage.classList.add('is-pulsing');
  clearTimeout(pulseTimer);
  pulseTimer = setTimeout(() => {
    stage.classList.remove('is-pulsing');
  }, 950);
}

document.getElementById('language').addEventListener('click', () => {
  setLanguage(language === 'en' ? 'zh' : 'en');
});

sourceSelect.addEventListener('change', updatePreview);
destSelect.addEventListener('change', updatePreview);
lockToggle.addEventListener('change', updatePreview);
micToggle.addEventListener('change', updatePreview);
sendPulseBtn.addEventListener('click', triggerPulse);

for (const btn of [wiredBtn, btBtn]) {
  btn.addEventListener('click', () => {
    mode = btn.id;
    wiredBtn.classList.toggle('active', mode === 'wired');
    btBtn.classList.toggle('active', mode === 'bluetooth');
    wiredBtn.setAttribute('aria-pressed', String(mode === 'wired'));
    btBtn.setAttribute('aria-pressed', String(mode === 'bluetooth'));
    updatePreview();
  });
}

setLanguage(language);
