'use strict';

const translations = {
  brandName: '键桥 KeyBridge',
  navFeatures: '特性',
  navConnections: '连接方式',
  navMic: '麦克风',
  navSetup: '开始使用',
  navFaq: '常见问题',
  navDownload: '下载',
  heroBadge: 'macOS 14+ · Apple Silicon 测试版 · MIT 开源',
  headline: '一副键盘，<br>两台 Mac。',
  intro: '从菜单栏把 MacBook 的键盘与内置触摸板应用到另一台 Mac。<br>外接鼠标，始终独立留在本机。',
  download: '下载 v1.6',
  viewGithub: '查看 GitHub',
  recommendedTag: '日常推荐',
  connectionPriority: '优先使用雷雳有线直连获得低延迟 · 蓝牙可作无线备用',
  previewNote: '交互演示 · 可切换设备、链路和开关体验工作状态',
  sendPulse: '模拟输入脉冲',
  sourceBadge: '输入来源',
  targetBadge: '正在接收输入',
  builtIn: '内置键盘与触摸板',
  yourOtherMac: '你的另一台 Mac',
  appName: '键桥',
  statusWired: '有线直连',
  device: '设备',
  applyTo: '应用于',
  wired: '有线直连',
  bluetoothLabel: '蓝牙',
  toggleLock: '防止自动锁屏',
  toggleMic: '共享麦克风',
  expShort: '实验',
  hintWired: '雷雳网桥低延迟连接 · 连接期间保持亮屏不锁屏',

  featuresEyebrow: '专为双 Mac 桌面打造',
  featureHeading: '点一下，接着打字。',
  featureIntro: '选择提供输入的 Mac，再选择要控制的 Mac。无主窗口、不推流画面，一切操作都在菜单栏一步完成。',
  featureOneTitle: '熟悉的键盘与触摸板，继续用。',
  featureOneBody: '在 MacBook 上顺手打字，支持原生功能键、指针移动、点击、拖动，以及保留自然滚动方向的完整连续双指滚动（v1.6）。还可开启实验性原生多指手势转发，把原生事件直接交给目标系统识别，而非写死成快捷键。',
  chipScroll: '连续双指滚动',
  chipFn: '原生功能键',
  chipGestures: '原生多指手势（实验）',
  featureTwoTitle: '鼠标，始终留在本机。',
  featureTwoBody: '显示器连接的外置鼠标不会被接管，始终留在本机可用。随时用它切换控制目标、重新连接或立即收回控制权；也支持快捷键一键应急返回。',
  emergencyLabel: '紧急切回本机',
  newIn16: '1.6 新增',
  featureLockTitle: '防止自动锁屏。',
  featureLockBody: '开启后，键桥会在连接期间持有进程级 macOS 显示器休眠断言，避免空闲 MacBook 在下一次输入前自动锁屏。不改系统全局锁屏设置，关闭或退出立即释放。',
  featureThreeTitle: '直连加密，无云端中转。',
  featureThreeBody: '两台 Mac 安装同一个轻量原生 Swift 应用。双端核对六位配对码并固定身份，输入经加密会话直连传输，无需账号、无服务器中转，也不会静默回退到 Wi-Fi。',
  featureRecoveryTitle: '断线即保护，稳妥恢复。',
  featureRecoveryBody: '断线、休眠、合盖或连接超时会立即停止拦截并释放远端按键。短暂心跳波动会自动收回并保留路由，恢复后无缝续接。',
  testedNote: '实机验证范围：已在 M1 Pro MacBook → M4 Mac mini（两台均为 macOS 15.8.1）的有线直连下完成实测，键盘、触摸板、原生多指手势与来源端输入隔离均正常。其他机型、系统及应用兼容性尚未全面验证。',

  connEyebrow: '连接链路',
  connectionHeading: '选择你的连接方式。',
  connectionIntro: '在菜单栏手动选择连接模式。键桥不会静默切换传输方式，也不会回退到 Wi-Fi。',
  tbTitle: '雷雳有线直连',
  thunderboltSub: '日常主力推荐 · 已实机验证',
  bestChoice: '最佳体验',
  thunderboltBody: '使用明确认证的 Thunderbolt 3 / 4 / 5 双 USB-C 线直连两台 Mac，建立 macOS「雷雳网桥」。若选购 USB4 线，需确认厂商明确支持雷雳兼容与 Mac 间雷雳网络；仅标注「100W」「全功能」「4K」并不足以判断可用。',
  tbSpec1: '键盘与触摸板响应延迟最低，手感最接近本机',
  tbSpec2: '支持实验性原生多指手势转发',
  tbSpec3: '支持实验性有线麦克风共享',
  bluetoothSub: '无需线缆 · 临时或备用',
  wirelessBackup: '无线备用',
  bluetoothBody: '手边没有雷雳线时，可通过蓝牙无线连接两台 Mac。蓝牙延迟相对较高（触摸板移动指针时更明显），建议作为临时或备用方案。',
  btSpec1: '支持打字、指针移动、点击、拖动与双指滚动',
  btSpec2: '延迟高于雷雳有线直连',
  btSpec3: '蓝牙模式不支持麦克风音频共享',

  portEyebrow: '硬件提示 · MAC MINI (2024)',
  portTitle: 'Mac mini M4 / M4 Pro 请插机身背面的雷雳接口。',
  portDesc: 'Mac mini（2024）机身正面的两个 USB-C 接口仅为 USB 3（10 Gb/s），无法建立雷雳网桥。请将雷雳线插入背面的三个雷雳接口之一（M4 为 Thunderbolt 4，M4 Pro 为 Thunderbolt 5）。',
  portFront: '机身正面（仅 USB 3）',
  portNo: '✕ 不支持雷雳网桥',
  portRear: '机身背面（Thunderbolt 4 / 5）',
  portYes: '✓ 任选背面雷雳接口',

  micEyebrow: '实验功能 · 仅限有线',
  microphoneHeading: '麦克风，也能用在另一台 Mac。',
  microphoneIntro: '通过已配对的加密雷雳连接共享麦克风。默认关闭，两端开关实时同步。',
  microphoneBody: '在菜单中勾选「原生多指手势」下方的「共享麦克风」，缺少连接、权限或组件时会按步骤引导补齐。只有来源采集与接收音频同时就绪，两端才会显示开启；任一端关闭即立即停止共享。',
  micPoint1: '48 kHz 单声道 PCM、20 ms 帧经加密有线链路传输（蓝牙不支持音频）',
  micPoint2: '接收端虚拟驱动经管理员批准安装一次后，自动局部重载，无需重启电脑',
  micPoint3: '在语音软件中选择 KeyBridge Microphone，绝不篡改系统默认麦克风',
  microphoneLimits: '实验状态说明：尚未完成双机语音软件实机验收，重连后不会自动恢复收音。',
  microphoneGuide: '查看麦克风安装与限制说明',
  sigSourceTitle: '来源 Mac 麦克风',
  sigSourceSub: '48 kHz · 单声道 PCM · 20 ms',
  sigPipe: '加密雷雳直连链路',
  sigTargetSub: 'Core Audio HAL · 免重启局部重载',

  setupEyebrow: '快速开始',
  setupHeading: '三步，两台 Mac 就绪。',
  setupIntro: '两台安装同一个应用、授权一次、核对六位配对码即可开始使用。',
  stepOneTitle: '安装同一个软件',
  stepOneBody: '在两台 Mac 上下载键桥 v1.6，先拖入「应用程序」再授权可避免重复弹窗。适用于 macOS 14 及以上的 Apple Silicon Mac。',
  stepTwoTitle: '开启所需权限',
  stepTwoBody: '来源 Mac 需开启「输入监控」与「辅助功能」；目标 Mac 需开启「辅助功能」。有线发现请允许本地网络，无线模式请允许蓝牙。',
  permInput: '输入监控',
  permAccess: '辅助功能',
  stepThreeTitle: '配对并选择路由',
  stepThreeBody: '核对两台 Mac 上的六位配对码并分别同意。在「设备」选来源、「应用于」选目标，路由会自动同步到另一台，无需重复设置。',
  permPair: '双端六位配对码',
  betaTitle: '测试版签名说明',
  betaNote: '当前开源测试版使用本地开发签名、未经 Apple 公证，首次打开可能触发系统拦截。确认来源后，可在「系统设置 → 隐私与安全性 → 仍要打开」放行；请勿全局关闭 Gatekeeper。',
  fullInstructions: '阅读完整安装指南',

  faqHeading: '常见问题。',
  faqLead: '关于线材、接口、手势、安全与测试版边界的坦诚说明。',
  faqIssues: '前往 GitHub 反馈问题',
  faqCableQ: '任意 USB-C 线都能用吗？',
  faqCableA: '不能。USB-C 只是接口外形。请优先选购明确标注 Thunderbolt 3 / 4 / 5 的双 USB-C 线并接入两台 Mac 的雷雳口；USB4 线需确认支持雷雳兼容与 Mac 间雷雳网络。仅标称 100W、全功能或 4K 视频并不能证明支持雷雳网桥。',
  faqPortQ: 'Mac mini 应该插哪个接口？',
  faqPortA: 'Mac mini M4 / M4 Pro 请使用机身背面的雷雳接口（M4 为 Thunderbolt 4，M4 Pro 为 Thunderbolt 5）。正面的两个 USB-C 接口仅为 USB 3（10 Gb/s），无法建立本软件所需的雷雳网桥。',
  faqGestureQ: '支持哪些触摸板手势？',
  faqGestureA: '移动、点击、拖动和连续双指滚动开箱可用。原生多指手势转发仍为实验功能且默认关闭，已在 M1 Pro → Mac mini M4（macOS 15.8.1）有线连接下实机确认可用；软件转发原生事件交由目标系统及应用自行解释，不映射为固定快捷键。',
  faqLockQ: 'MacBook 操作另一台 Mac 时自动锁屏怎么办？',
  faqLockA: '在键桥中开启「防止自动锁屏」。两台 Mac 连接期间，键桥会持有进程级 macOS 显示器休眠断言，避免空闲倒计时锁屏。关闭开关或退出键桥立即释放；手动锁屏、合盖和系统休眠仍会暂停转发，且绝不修改全局锁屏设置。',
  faqWifiQ: '会使用 Wi-Fi 吗？',
  faqWifiA: '不会。键桥仅提供雷雳网桥直连与蓝牙两种手动模式，不会回退到 Wi-Fi，也不会在链路之间静默切换。',
  faqMouseQ: '可以用鼠标恢复本机输入吗？',
  faqMouseA: '可以。外接鼠标始终留在本机，随时点击菜单栏切回本机、停止转发或重连；也可以随时按下 Control–Option–Command–Escape 紧急切回。',
  faqInstallQ: '为什么首次打开测试版会有系统警告？',
  faqInstallA: '当前测试版采用本地开发签名，未购买 Apple Developer ID 签名及公证，因此 macOS 会提示风险。确认来源后，请通过「系统设置 → 隐私与安全性 → 仍要打开」启动，切勿全局关闭 Gatekeeper。',
  faqPrivacyQ: '两台 Mac 之间会传输什么？',
  faqPrivacyA: '键盘与触摸板输入通过已认证的加密会话在配对 Mac 间点对点传输；可选麦克风仅在开启后通过有线链路传输音频，绝不传输屏幕画面。诊断日志不包含键入文本或原始手势内容，但可能包含设备名和局域网信息。',

  ctaHeading: '准备好桥接你的两台 Mac 了吗？',
  ctaBody: '免费、开源、原生 Swift 构建，支持 macOS 14+ 与 Apple Silicon。',
  releaseNotes: '查看 1.6 发布说明',
  chineseName: '/ 键桥',
  releases: '版本发布',
  architecture: '架构说明',
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
const themeToggleBtn = document.getElementById('theme-toggle');
const themeColorMeta = document.getElementById('theme-color-meta');
const metaDescription = document.getElementById('meta-description');

const metaDescByLang = {
  en: 'KeyBridge (键桥) is a free, open-source macOS menu bar app that shares your MacBook keyboard, trackpad, and experimental wired microphone with another Mac over direct Thunderbolt or Bluetooth. Keep your external mouse independent.',
  zh: '键桥（KeyBridge）是一款免费开源的 macOS 菜单栏工具，可通过雷雳有线直连或蓝牙把 MacBook 的键盘、内置触摸板及实验性有线麦克风共享给另一台 Mac，同时保持外接鼠标本机独立可用。'
};

function applyTheme(theme, persist) {
  document.documentElement.dataset.theme = theme;
  if (themeColorMeta) {
    themeColorMeta.setAttribute('content', theme === 'light' ? '#f5f5f7' : '#0a0a0b');
  }
  updateThemeLabel();
  if (persist) {
    try {
      localStorage.setItem('keybridge-theme', theme);
    } catch (e) {}
  }
}

function updateThemeLabel() {
  if (!themeToggleBtn) return;
  const isLight = document.documentElement.dataset.theme === 'light';
  const label = language === 'zh'
    ? (isLight ? '切换到深色模式' : '切换到浅色模式')
    : (isLight ? 'Switch to dark mode' : 'Switch to light mode');
  themeToggleBtn.setAttribute('aria-label', label);
  themeToggleBtn.setAttribute('title', label);
}

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
  document.title = value === 'zh' ? '键桥 KeyBridge — 一副键盘，两台 Mac。' : 'KeyBridge — One keyboard. Two Macs.';
  if (metaDescription) {
    metaDescription.setAttribute('content', metaDescByLang[value]);
  }
  updateThemeLabel();

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
    demoRoute.textContent = language === 'zh' ? '本机输入 · 未转发' : 'Local input · paused';
    demoStatus.textContent = language === 'zh' ? '本机' : 'Local';
    macbookBadge.textContent = language === 'zh' ? '本机独立' : 'Local only';
    miniBadge.textContent = language === 'zh' ? '本机独立' : 'Local only';
    demoHint.textContent = language === 'zh'
      ? '输入保留在本机 · 随时选择目标 Mac 恢复桥接'
      : 'Input stays local · pick another Mac to bridge';
    return;
  }

  demoRoute.textContent = `${names[src]} → ${names[dst]}`;
  demoStatus.textContent = isBt
    ? (language === 'zh' ? '蓝牙' : 'Bluetooth')
    : (language === 'zh' ? '有线直连' : 'Wired');

  if (src === 'macbook') {
    macbookBadge.textContent = language === 'zh' ? '输入来源' : 'Input source';
    miniBadge.textContent = language === 'zh' ? '正在接收输入' : 'Receiving input';
  } else {
    macbookBadge.textContent = language === 'zh' ? '正在接收输入' : 'Receiving input';
    miniBadge.textContent = language === 'zh' ? '输入来源' : 'Input source';
  }

  if (isBt) {
    demoHint.textContent = lockActive
      ? (language === 'zh' ? '蓝牙备用链路 · 已开启防止自动锁屏（音频需有线）' : 'Bluetooth backup · display stays awake (audio requires cable)')
      : (language === 'zh' ? '蓝牙备用链路 · 延迟相对较高（音频需有线）' : 'Bluetooth backup · higher latency (audio requires cable)');
  } else if (micActive) {
    demoHint.textContent = language === 'zh'
      ? '雷雳低延迟 + 48 kHz 加密麦克风音频正在传输'
      : 'Low-latency Thunderbolt + 48 kHz encrypted mic active';
  } else {
    demoHint.textContent = lockActive
      ? (language === 'zh' ? '雷雳网桥低延迟连接 · 连接期间保持亮屏不锁屏' : 'Low-latency Thunderbolt Bridge · display stays awake')
      : (language === 'zh' ? '雷雳网桥低延迟连接 · 支持原生手势与有线麦克风' : 'Low-latency Thunderbolt Bridge · gestures & wired mic ready');
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

if (themeToggleBtn) {
  themeToggleBtn.addEventListener('click', () => {
    const next = document.documentElement.dataset.theme === 'light' ? 'dark' : 'light';
    applyTheme(next, true);
  });
}

if (window.matchMedia) {
  window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', (event) => {
    try {
      if (!localStorage.getItem('keybridge-theme')) {
        applyTheme(event.matches ? 'light' : 'dark', false);
      }
    } catch (e) {}
  });
}

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
