// 單頁網頁 UI。配色與排版參考 DragonVM 的冷灰 + 琥珀金風格,
// 但為了節省手機 GPU,不使用 backdrop-filter(毛玻璃模糊)、光暈陰影與動畫。
let webPage = #"""
<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="theme-color" content="#2E2F31">
<link rel="manifest" href="/manifest.webmanifest">
<link rel="icon" type="image/png" href="/icon-192.png">
<link rel="apple-touch-icon" href="data:image/png;base64,\#(PWA.appleTouchIconBase64)">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="Parallels">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>Parallels Remote</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<!-- 非阻塞載入 Inter:先用系統字型立刻顯示,字型載好後再替換;外網不通時頁面也不會卡白 -->
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" media="print" onload="this.media='all'">
<noscript><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"></noscript>
<style>
:root {
  --bg: #3C3F41; --surface: #2E2F31; --surface-hi: #4D5053; --border: rgba(255,255,255,0.12);
  --text: #FFFFFF; --muted: #BFC3C5; --gray: #747474;
  --accent: #FFD700; --accent-hover: #E6C200;
  --green: #4caf50; --red: #ef9a9a; --red-bg: rgba(229,57,53,0.16);
}
* { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }
html { background: var(--bg); touch-action: manipulation; }   /* 禁止雙擊放大(仍可正常捲動) */
/* 禁止選取文字與長按選單;輸入框例外,否則無法輸入 */
body { -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; }
input, textarea { -webkit-user-select: text; user-select: text; }
body {
  min-height: 100vh; color: var(--text); font-size: 15px; line-height: 1.45;
  font-family: '-apple-system', 'BlinkMacSystemFont', 'SF Pro', 'SF Pro Display', 'PingFang TC', 'Inter', 'Roboto', 'AppleGothic', 'Microsoft JhengHei UI', sans-serif;
  background: linear-gradient(160deg, #9E9E9E 0%, #6F7174 40%, #4A4B4D 100%);
  padding: 0 0 calc(80px + env(safe-area-inset-bottom));
}
header {
  position: sticky; top: 0; z-index: 50;
  display: flex; align-items: center; gap: 10px;
  /* PWA 全螢幕時內容會延伸到狀態列 / 動態島底下,標題列要自己留出安全區域 */
  padding: calc(max(env(safe-area-inset-top), var(--sat, 0px)) + 16px) calc(16px + env(safe-area-inset-right)) 12px calc(16px + env(safe-area-inset-left));
  background: var(--surface); border-bottom: 1px solid var(--border);
}
header { gap: 8px; }
header h1 { flex: 1; font-size: 18px; font-weight: 700; letter-spacing: -0.3px; }
main { max-width: 720px; margin: 0 auto; padding: 14px max(12px, env(safe-area-inset-right)) 0 max(12px, env(safe-area-inset-left)); display: flex; flex-direction: column; gap: 14px; }

/* 按鈕 */
button, select, input { font-family: inherit; }
.btn {
  height: 38px; padding: 0 14px; border-radius: 12px; cursor: pointer; font-size: 14px; font-weight: 500;
  color: var(--accent); background: var(--surface-hi); border: 1px solid var(--border);
}
.btn:active { background: #5a5e61; }
.btn:disabled { opacity: .45; cursor: default; }
.btn.primary { background: var(--accent); color: #1a1a1a; border-color: transparent; font-weight: 600; }
.btn.primary:active { background: var(--accent-hover); }
.btn.green { color: #81c784; background: rgba(76,175,80,0.16); border-color: rgba(76,175,80,0.35); }
.btn.danger { color: var(--red); background: var(--red-bg); border-color: rgba(239,154,154,0.25); }
.btn.icon { width: 42px; height: 42px; padding: 0; display: flex; align-items: center; justify-content: center; }
.btn.icon svg { width: 22px; height: 22px; fill: currentColor; }
.btn.small { height: 30px; padding: 0 12px; border-radius: 16px; font-size: 12px; }
.btn.small.icon { width: 32px; padding: 0; }
.btn.small.icon svg { width: 16px; height: 16px; }

/* 機器卡片 */
.card { background: var(--surface); border: 1px solid var(--border); border-radius: 16px; padding: 14px; }
.vm-head { display: flex; align-items: center; gap: 10px; }
.dot { width: 10px; height: 10px; border-radius: 50%; flex: none; background: var(--gray); }
.dot.running { background: var(--green); }
.dot.paused { background: var(--accent); }
.dot.suspended { background: #4dd0c4; }
.vm-name { flex: 1; min-width: 0; font-size: 16px; font-weight: 700; overflow-wrap: anywhere; }
.chip { flex: none; font-size: 12px; color: var(--muted); background: var(--surface-hi); padding: 2px 10px; border-radius: 10px; }
.chip.running { color: #81c784; background: rgba(76,175,80,0.14); }
.chip.paused { color: var(--accent); background: rgba(255,215,0,0.12); }
.chip.suspended { color: #4dd0c4; background: rgba(77,208,196,0.14); }
.ips { margin-top: 8px; display: flex; flex-direction: column; gap: 6px; font-size: 12px; color: var(--muted); }
.ip:active { background: var(--surface-hi); }
.ip-row { display: flex; align-items: center; gap: 8px; }
.ip { cursor: pointer; font-size: 14px; color: var(--text); background: var(--bg); padding: 2px 8px; border-radius: 8px; }
.net { flex: none; min-width: 64px; text-align: center; font-size: 11px; padding: 2px 8px; border-radius: 8px; color: var(--accent); background: rgba(255,215,0,0.12); }
#vms { display: flex; flex-direction: column; gap: 14px; }
.actions { margin-top: 12px; display: flex; flex-wrap: wrap; gap: 8px; }

details.card > summary { list-style: none; cursor: pointer; }
details.card > summary::-webkit-details-marker { display: none; }
details.card > .vm-body { margin-top: 0; }

/* 區塊(端口轉發 / 快照) */
.sub { margin-top: 12px; background: var(--bg); border: 1px solid var(--border); border-radius: 14px; padding: 12px; }
.sub-title { font-size: 13px; font-weight: 700; margin-bottom: 8px; display: flex; align-items: center; gap: 6px; }
.sub-title small { font-weight: 400; color: var(--muted); font-size: 11px; }
/* 規格滑桿(CPU / 記憶體),樣式參考 DragonGuardian 的 .form-slider:金色填充、橢圓玻璃把手 */
.spec-line { font-weight: 400; font-size: 12px; color: var(--muted); }
.spec-row { margin-top: 10px; }
.spec-label { display: flex; justify-content: space-between; font-size: 13px; }
.spec-label b { color: var(--accent); font-weight: 600; }
.slider-wrap { position: relative; display: block; width: 100%; margin: 14px 0 4px; }
.slider-wrap::before { content: ''; position: absolute; left: 0; right: 0; top: 0; height: 8px; border-radius: 9999px;
  background: rgba(128,128,128,0.18); box-shadow: inset 0 1px 2px rgba(0,0,0,0.18); pointer-events: none; }
/* 金色填充:兩端全圓角,右端是半圓結尾;停止點對齊把手中心(把手寬 18px) */
.slider-fill { position: absolute; left: 0; top: -1px; height: 10px; width: var(--sl-stop, 9px); border-radius: 9999px;
  background: var(--accent); box-shadow: 0 2px 5px rgba(0,0,0,0.35); z-index: 1; pointer-events: none; }
.slider-wrap:has(.form-slider:disabled) .slider-fill { background: rgba(128,128,128,0.45); box-shadow: none; }
.form-slider { display: block; width: 100%; -webkit-appearance: none; appearance: none; height: 8px; margin: 0;
  border-radius: 9999px; outline: none; cursor: pointer; padding: 0; border: none; background: transparent; position: relative; z-index: 2; }
.form-slider::-webkit-slider-thumb { -webkit-appearance: none; width: 18px; height: 30px; border-radius: 9px; cursor: pointer;
  background: linear-gradient(135deg, rgba(255,255,255,0.40) 0%, rgba(228,228,228,0.24) 100%);
  border: 0.5px solid rgba(255,255,255,0.46);
  box-shadow: 0 2px 8px rgba(0,0,0,0.16), 0 0 0 0.5px rgba(0,0,0,0.05), inset 0 1px 0 rgba(255,255,255,0.40), 0 0 8px rgba(255,215,0,0.18);
  transition: transform .1s, box-shadow .45s, background .45s; }
.form-slider:not(:disabled)::-webkit-slider-thumb:active { transform: scale(1.12);
  background: linear-gradient(135deg, rgba(255,255,255,0.92) 0%, rgba(245,245,245,0.72) 100%); border-color: rgba(255,255,255,0.85);
  box-shadow: 0 4px 14px rgba(0,0,0,0.24), 0 0 14px rgba(255,215,0,0.42); transition: transform .1s, background .06s; }
.form-slider:disabled { cursor: not-allowed; }
.form-slider:disabled::-webkit-slider-thumb { background: rgba(128,128,128,0.3); box-shadow: none; border: none; }
/* 刻度:位置公式與 .slider-fill 的停止點一致,數字才會對準把手實際停留處 */
.slider-ticklabels { position: relative; height: 14px; margin: 18px 0 6px; font-size: 10px; color: var(--muted); pointer-events: none; }
.slider-ticklabels span { position: absolute; top: 0; transform: translateX(-50%); white-space: nowrap; }
.slider-ticklabels span::before { content: ''; position: absolute; left: 50%; top: -9px; width: 4px; height: 4px; border-radius: 50%;
  background: rgba(255,255,255,0.4); transform: translateX(-50%); }
.slider-ticklabels.dim { opacity: .35; }
.spec-actions { margin-top: 10px; display: flex; align-items: center; gap: 8px; }
.empty { font-size: 12px; color: var(--muted); padding: 2px 0 6px; }
.row { display: flex; align-items: center; gap: 8px; padding: 6px 0; border-bottom: 1px solid var(--border); font-size: 13px; }
.row:last-of-type { border-bottom: none; }
.row .grow { flex: 1; min-width: 0; overflow-wrap: anywhere; }
.row .mono { }
.row .note { font-size: 11px; color: var(--muted); }
details.sub > summary { cursor: pointer; font-size: 13px; font-weight: 700; list-style: none; display: flex; align-items: center; gap: 6px; }
details.sub > summary::-webkit-details-marker { display: none; }
details.sub > summary .grow { flex: 1; }
.caret { width: 28px; height: 28px; border-radius: 8px; flex: none; display: flex; align-items: center; justify-content: center;
  color: var(--accent); background: var(--surface-hi); }
.caret svg { width: 20px; height: 20px; fill: currentColor; transition: transform .2s ease; }
details[open] > summary .caret svg { transform: rotate(180deg); }
details.sub > .body { margin-top: 8px; }

/* 表單 */
.fw-add { margin-top: 6px; }
form.fw[hidden] { display: none; }
form.fw { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 8px; }
form.fw .arrow { color: var(--muted); }
select, input[type=number] {
  height: 38px; padding: 0 10px; border-radius: 10px; color: var(--text); font-size: 16px;
  background: var(--surface-hi); border: 1px solid rgba(128,128,128,0.35); outline: none;
}
input[type=number] { width: 78px; padding: 0 8px; }
form.fw select { padding: 0 6px; }
select option { background: var(--surface); color: var(--text); }
select:focus, input:focus { border-color: var(--accent); }

/* 網頁內對話框(取代 alert/confirm/prompt);比照 Dragon 的堆疊式全寬按鈕,不使用模糊 */
#dg-overlay { position: fixed; inset: 0; z-index: 100; display: flex; align-items: center; justify-content: center;
  padding: 24px; background: rgba(0,0,0,0.6); }
.dg-dialog { width: min(420px, 100%); max-height: calc(100vh - 48px); overflow-y: auto; background: var(--bg);
  border: 1px solid var(--border); border-radius: 16px; }
.dg-title { padding: 24px 20px 0; font-size: 20px; font-weight: 700; }
.dg-body { padding: 12px 20px 0; font-size: 16px; line-height: 1.4; white-space: pre-wrap; overflow-wrap: anywhere; }
.dg-input { width: 100%; margin-top: 12px; height: 44px; padding: 0 12px; border-radius: 10px; font-size: 16px; color: var(--text);
  background: rgba(0,0,0,0.2); border: 1px solid rgba(255,255,255,0.16); outline: none; }
.dg-input:focus { border-color: var(--accent); }
.dg-foot { display: flex; flex-direction: column; gap: 12px; padding: 24px 20px 20px; }
.dg-btn { width: 100%; height: 45px; padding: 0 18px; border-radius: 10px; font-size: 16px; font-weight: 700; letter-spacing: .5px;
  cursor: pointer; border: 1.5px solid transparent; background: transparent; color: var(--text); }
.dg-btn-primary { background: var(--accent); color: #2E2F31; border-color: var(--accent); }
.dg-btn-white { color: #fff; border-color: #fff; }
.dg-btn-red { color: var(--red); border-color: var(--red); }
.dg-btn:active { filter: brightness(1.15); }

/* 提示訊息 */
#msg {
  position: fixed; left: 12px; right: 12px; bottom: calc(14px + env(safe-area-inset-bottom)); z-index: 20;
  max-width: 696px; margin: 0 auto; padding: 12px 16px; border-radius: 12px; font-size: 14px;
  background: var(--surface); border: 1px solid var(--accent); color: var(--text); display: none;
}
#msg.err { border-color: #ef5350; color: var(--red); }
#msg.show { display: block; }
.note-top { font-size: 12px; color: var(--muted); padding: 0 4px; }
</style>
</head>
<body>
<header>
  <h1>Parallels Remote</h1>
  <button class="btn icon" id="account" hidden onclick="accountDialog().catch(e => msg('錯誤: ' + e.message, true))" aria-label="帳號" title="帳號">
    <svg viewBox="0 0 24 24"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
  </button>
  <button class="btn icon" id="refresh" onclick="load()" aria-label="重新整理" title="重新整理">
    <svg viewBox="0 0 24 24"><path d="M17.65 6.35A7.958 7.958 0 0 0 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0 1 12 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/></svg>
  </button>
</header>
<main>
  <div id="vms"></div>
  <div id="otherfw"></div>
</main>
<div id="msg"></div>
<script>
const $ = id => document.getElementById(id);
// iOS 加到主畫面後 env(safe-area-inset-top) 不一定可靠,標題列會被動態島 / 狀態列蓋住。
// 動態島機型(螢幕高 852 / 874 / 932 / 956 pt)的狀態列約 59~62pt,直接給保底值。
if (navigator.standalone === true && [852, 874, 932, 956].includes(Math.max(screen.width, screen.height))) {
  document.documentElement.style.setProperty('--sat', '62px');
}
const STATUS = { stopped: '已關機', running: '執行中', suspended: '已休眠', paused: '已暫停' };
const openSnaps = new Set();
const openSpecs = new Set();
const openVMs = new Set();
let msgTimer;
const norm = id => id.replace(/[{}]/g, '').toLowerCase();

// 區網 http 不是 secure context,navigator.clipboard 不可用,所以用 textarea + execCommand 當後備
async function copyText(text) {
  let ok = false;
  try { if (navigator.clipboard && window.isSecureContext) { await navigator.clipboard.writeText(text); ok = true; } } catch (e) {}
  if (!ok) {
    const t = el('textarea', { value: text });
    t.style.cssText = 'position:fixed;top:0;left:0;opacity:0';
    document.body.append(t); t.focus(); t.select();
    try { ok = document.execCommand('copy'); } catch (e) {}
    t.remove();
  }
  msg(ok ? '已拷貝 ' + text : '拷貝失敗,請手動複製 ' + text, !ok);
}
const COPY_SVG = '<svg viewBox="0 0 24 24"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>';
function copyBtn(text, label) {
  const b = el('button', { type: 'button', className: 'btn small icon', title: label, onclick: () => copyText(text) });
  b.setAttribute('aria-label', label);
  b.innerHTML = COPY_SVG;
  return b;
}

// 取消操作:丟出 CANCEL 會讓 btn() 靜默結束,不顯示錯誤
const CANCEL = { cancelled: true };

// 網頁內對話框(Promise)。buttons: [{ label, cls, value }];有 input 時按鈕 value 為 INPUT 代表回傳輸入內容
const INPUT = Symbol('input');
function dgDialog({ title, body, input, inputType, buttons, cancelValue, modal }) {
  return new Promise(resolve => {
    const ov = el('div', { id: 'dg-overlay' });
    const done = v => { ov.remove(); resolve(v); };
    const box = el('div', { className: 'dg-dialog' }, el('div', { className: 'dg-title', textContent: title }));
    if (body) box.append(el('div', { className: 'dg-body', textContent: body }));
    let inp;
    if (input !== undefined) {
      inp = el('input', { className: 'dg-input', type: inputType || 'text', value: input });
      if (inputType === 'password') inp.autocomplete = 'current-password';
      box.append(el('div', { className: 'dg-body' }, inp));
    }
    const foot = el('div', { className: 'dg-foot' });
    for (const b of buttons) foot.append(el('button', { className: 'dg-btn ' + b.cls, textContent: b.label,
      onclick: () => done(b.value === INPUT ? inp.value : b.value) }));
    box.append(foot);
    ov.append(box);
    if (!modal) ov.onclick = e => { if (e.target === ov) done(cancelValue); };   // modal:只能按按鈕,點旁邊不會關閉
    if (inp) inp.onkeydown = e => { if (e.key === 'Enter') done(inp.value); };
    document.body.append(ov);
    if (inp) { inp.focus(); inp.select(); }
  });
}
// 確認:回傳 true / false。danger = true 時確認鈕用紅色
const dgConfirm = (title, body, ok = '確認', danger = false) => dgDialog({
  title, body, cancelValue: false,
  buttons: [{ label: ok, cls: danger ? 'dg-btn-red' : 'dg-btn-primary', value: true }, { label: '取消', cls: 'dg-btn-white', value: false }] });
// 輸入:回傳字串,取消回傳 null
const dgPrompt = (title, body, def = '', ok = '確認', type = 'text') => dgDialog({
  title, body, input: def, inputType: type, cancelValue: null,
  buttons: [{ label: ok, cls: 'dg-btn-primary', value: INPUT }, { label: '取消', cls: 'dg-btn-white', value: null }] });

// ───────── 登入(密碼在 Mac 的設定視窗設定)與登出 ─────────
let loginPromise = null;
function ensureLogin() {
  if (!loginPromise) loginPromise = loginDialog().finally(() => { loginPromise = null; });
  return loginPromise;
}
async function loginDialog() {
  let note = '請輸入密碼。';
  for (;;) {
    // 登入是必要步驟:沒有取消鈕,點旁邊也不會關閉
    const r = await dgDialog({ title: '登入', body: note, input: '', inputType: 'password', modal: true,
      buttons: [{ label: '登入', cls: 'dg-btn-primary', value: INPUT }] });
    try { await rawApi('POST', 'login', { password: r }); msg(''); return; }
    catch (e) { note = '登入失敗:' + e.message; }
  }
}
// 帳號視窗:登出(沒有設定密碼時右上角的人頭圖示不會顯示)
async function accountDialog() {
  if (!await dgConfirm('登出?', '登出後需要重新輸入密碼才能控制虛擬機。', '登出', true)) return;
  await rawApi('POST', 'logout');
  location.reload();   // 重新載入,清掉畫面上殘留的機器清單與狀態;載入後會自動跳出登入視窗
}

// 本機時間 YYYY-MM-DD HH:mm:ss
function nowStamp() {
  const d = new Date(), p = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

function msg(t, isErr) {
  const m = $('msg');
  clearTimeout(msgTimer);
  if (!t) { m.className = ''; return; }
  m.textContent = t;
  m.className = 'show' + (isErr ? ' err' : '');
  msgTimer = setTimeout(() => { m.className = ''; }, isErr ? 8000 : 3500);   // 錯誤提示也會自動消失
}
function el(tag, props, ...kids) {
  const e = document.createElement(tag);
  Object.assign(e, props || {});
  for (const k of kids) e.append(k);
  return e;
}
// Material 圖示路徑(沿用 Dragon 專案的圖示選擇)
const ICONS = {
  start: 'M8 5v14l11-7z',                                               // play_arrow:開機 / 恢復
  pause: 'M6 19h4V5H6v14zm8-14v14h4V5h-4z',                             // pause:暫停
  hibernate: 'M12.34 2.02C6.59 1.82 2 6.42 2 12c0 5.52 4.48 10 10 10 3.71 0 6.93-2.02 8.66-5.02-7.51-.25-12.09-8.43-8.32-14.96z', // bedtime:休眠
  stop: 'M13 3h-2v10h2V3zm4.83 2.17l-1.42 1.42C17.99 7.86 19 9.81 19 12c0 3.87-3.13 7-7 7s-7-3.13-7-7c0-2.19 1.01-4.14 2.58-5.42L6.17 5.17C4.23 6.82 3 9.26 3 12c0 4.97 4.03 9 9 9s9-4.03 9-9c0-2.74-1.23-5.18-3.17-6.83z', // power_settings_new:正常關機
  kill: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm4 14H8V8h8v8z', // stop_circle:強制關機
  clone: 'M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-1 9h-4v4h-2v-4H9V9h4V5h2v4h4v2z', // add_to_photos:複製機器
  revert: 'M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z', // history:回復到最後一個快照
  plug: 'M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z', // link:連回網卡
  unplug: 'M17 7h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1 0 1.43-.98 2.63-2.31 3l1.46 1.44C20.88 15.61 22 13.95 22 12c0-2.76-2.24-5-5-5zm-1 4h-2.19l2 2H16zM2 4.27l3.11 3.11C3.29 8.12 2 9.91 2 12c0 2.76 2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1 0-1.59 1.21-2.9 2.76-3.07L8.73 11H8v2h2.73L13 15.27V17h1.73l4.01 4L20 19.74 3.27 3 2 4.27z', // link_off:拔掉網卡
  del: 'M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z' // delete:刪除
};
function btn(label, fn, cls, icon) {
  const b = el('button', { className: 'btn ' + (cls || '') });
  if (icon) {   // 圖示按鈕:文字只留給 title / 螢幕閱讀器
    b.className += ' icon';
    b.title = label;
    b.setAttribute('aria-label', label);
    b.innerHTML = '<svg viewBox="0 0 24 24"><path d="' + ICONS[icon] + '"/></svg>';
  } else b.textContent = label;
  b.onclick = async () => {
    b.disabled = true;
    msg('處理中…');
    try { await fn(); if ($('msg').textContent === '處理中…') msg('完成'); }
    catch (e) { if (e === CANCEL) msg(''); else msg('錯誤: ' + e.message, true); }
    b.disabled = false;
    load();
  };
  return b;
}
async function rawApi(method, path, body) {
  const r = await fetch('/api/' + path, { method, headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) { const e = new Error(j.error || r.status); e.status = r.status; throw e; }
  return j;
}
// 一般 API:需要登入(401)就跳出登入對話框,登入成功後自動重試一次
async function api(method, path, body) {
  try { return await rawApi(method, path, body); }
  catch (e) { if (e.status !== 401) throw e; await ensureLogin(); return rawApi(method, path, body); }
}

async function cloneVM(v) {
  const live = v.status === 'running';
  const name = await dgPrompt('複製機器',
    live ? '這台正在執行:會先休眠它、複製完再自動恢復,期間連線會暫停。\n\n新機器的名稱(留空使用預設):' : '新機器的名稱(留空使用預設):',
    v.name + ' copy', '複製');
  if (name === null) throw CANCEL;
  msg('複製中,請稍候…');
  const r = await api('POST', `vm/${v.uuid}/clone`, { start: false, name });
  msg('已建立 ' + r.name + ',SSH 轉發埠 ' + r.sshPort + (r.warnings.length ? '(警告: ' + r.warnings.join('; ') + ')' : ''));
}
async function deleteVM(v) {
  // 按鈕確認即可;伺服器端仍要求帶上名稱,由這裡自動帶入,避免有人直接打 API 誤刪
  if (!await dgConfirm('刪除「' + v.name + '」?', '會永久刪除這台機器和它的所有檔案,無法復原。', '刪除', true)) throw CANCEL;
  await api('DELETE', `vm/${v.uuid}`, { confirmName: v.name });
}
async function revertVM(v) {
  if (!await dgConfirm('回復到最後一個快照?', '「' + v.name + '」會回到最後一個快照的狀態,之後所做的變更都會遺失。', '回復', true)) throw CANCEL;
  const r = await api('POST', `vm/${v.uuid}/revert`);
  msg('已回復到快照「' + r.snapshot + '」');
}

function fwForm(vm) {
  const proto = el('select', {}, el('option', { textContent: 'tcp' }), el('option', { textContent: 'udp' }));
  const mk = ph => el('input', { type: 'number', min: 1, max: 65535, required: true, placeholder: ph, inputMode: 'numeric' });
  const src = mk('Mac 埠'), dst = mk('VM 埠');
  const form = el('form', { className: 'fw', hidden: true, onsubmit: async ev => {
    ev.preventDefault();
    try {
      await api('POST', 'forwards', { proto: proto.value, sourcePort: +src.value, target: vm.uuid, destPort: +dst.value });
      msg('已新增轉發');
    } catch (e) { msg('錯誤: ' + e.message, true); }
    load();
  }}, proto, src, el('span', { className: 'arrow', textContent: '→' }), dst,
     el('button', { className: 'btn small primary', textContent: '新增' }));
  // 輸入框預設收起,按「＋ 新增轉發」才展開
  const toggle = el('button', { type: 'button', className: 'btn small', textContent: '＋ 新增轉發' });
  toggle.onclick = () => {
    form.hidden = !form.hidden;
    toggle.textContent = form.hidden ? '＋ 新增轉發' : '－ 收起';
    if (!form.hidden) src.focus();
  };
  return el('div', { className: 'fw-add' }, toggle, form);
}
function fwRow(f, label) {
  const row = el('div', { className: 'row' },
    el('div', { className: 'grow' },
      el('span', { className: 'mono', textContent: `${f.proto} :${f.sourcePort} → ${label}:${f.destPort}` }),
      f.managed ? '' : el('div', { className: 'note', textContent: '手動建立的規則(請在 Parallels 內管理)' })));
  // 轉發埠開在 Mac 上,所以拷貝「目前連線用的位址:Mac 埠」
  row.append(copyBtn(`${location.hostname}:${f.sourcePort}`, '拷貝 ' + location.hostname + ':' + f.sourcePort));
  if (f.managed) row.append(btn('刪除', () => api('DELETE', `forwards/${f.name}`), 'small danger'));
  return row;
}

// 快照清單:首次才顯示「載入中…」;之後靜默抓取,內容沒變就完全不動
async function fillSnaps(vm, body) {
  if (!body.dataset.sig) body.replaceChildren(el('div', { className: 'empty', textContent: '載入中…' }));
  try {
    const { snapshots } = await api('GET', `vm/${vm.uuid}/snapshots`);
    const sig = JSON.stringify(snapshots);
    if (body.dataset.sig === sig) return;
    body.dataset.sig = sig;
    const kids = [];
    if (!snapshots.length) kids.push(el('div', { className: 'empty', textContent: '(沒有快照)' }));
    for (const s of snapshots) {
      const row = el('div', { className: 'row' },
        el('div', { className: 'grow' }, (s.current ? '● ' : '') + s.name,
          el('div', { className: 'note', textContent: s.date })),
        btn('還原', async () => { if (!await dgConfirm('還原快照?', '還原到「' + s.name + '」,目前未存的狀態會遺失。', '還原', true)) throw CANCEL; await api('POST', `vm/${vm.uuid}/snapshots/${s.id}/switch`); }, 'small'),
        btn('刪除', async () => { if (!await dgConfirm('刪除快照?', '刪除快照「' + s.name + '」。', '刪除', true)) throw CANCEL; await api('DELETE', `vm/${vm.uuid}/snapshots/${s.id}`); }, 'small danger'));
      kids.push(row);
    }
    kids.push(el('div', { className: 'actions' }, btn('建立快照', async () => {
      const now = nowStamp();   // 預設名稱 = 當下時間;留空也用當下時間
      const input = await dgPrompt('建立快照', '快照名稱(預設為目前時間):', now, '建立');
      if (input === null) throw CANCEL;
      const n = input.trim() || now;
      await api('POST', `vm/${vm.uuid}/snapshots`, { name: n });
    }, 'small primary')));
    body.replaceChildren(...kids);
  } catch (e) { delete body.dataset.sig; body.replaceChildren(el('div', { className: 'empty', textContent: '錯誤: ' + e.message })); }
}
const CARET_SVG = '<svg viewBox="0 0 24 24"><path d="M16.59 8.59 12 13.17 7.41 8.59 6 10l6 6 6-6z"/></svg>';
function caret() { const c = el('span', { className: 'caret' }); c.innerHTML = CARET_SVG; return c; }
function snapSection(vm) {
  const body = el('div', { className: 'body' });
  const d = el('details', { className: 'sub' }, el('summary', {}, el('span', { className: 'grow', textContent: '快照' }), caret()), body);
  d.open = openSnaps.has(vm.uuid);
  if (d.open) fillSnaps(vm, body);
  d.addEventListener('toggle', () => {
    if (d.open) { openSnaps.add(vm.uuid); fillSnaps(vm, body); } else openSnaps.delete(vm.uuid);
  });
  return { node: d, body };
}

// ───────── 每張卡片拆成幾個區塊,各自用「內容特徵」判斷要不要重畫 ─────────
function partHead(v) {
  return el('div', { className: 'vm-head' }, el('span', { className: 'dot ' + v.status }),
    el('span', { className: 'vm-name', textContent: v.name }), caret());
}
function partIps(v) {
  // v.ips: [{ip, net}];停止中的機器沒有 IP
  const ips = (v.ips && v.ips.length) ? v.ips : (v.ip_configured && v.ip_configured !== '-' ? [{ ip: v.ip_configured, net: '' }] : []);
  const ipRow = el('div', { className: 'ips' });
  ipRow.append(el('div', { className: 'ip-row' }, el('span', { className: 'net', textContent: '狀態' }), el('span', { className: 'chip ' + v.status, textContent: STATUS[v.status] || v.status })));
  if (ips.length) for (const i of ips) ipRow.append(el('div', { className: 'ip-row' },
    el('span', { className: 'net', textContent: i.net || 'IP' }), el('span', { className: 'ip', textContent: i.ip, title: '點一下拷貝', onclick: () => copyText(i.ip) })));
  else ipRow.append(el('div', { className: 'ip-row' }, el('span', { className: 'net', textContent: 'IP' }), el('span', { textContent: '—' })));
  return ipRow;
}
function partActions(v) {
  const run = v.status === 'running', susp = v.status === 'suspended', paused = v.status === 'paused';
  const actions = el('div', { className: 'actions' });
  const revertBtn = () => btn('回復到最後一個快照', () => revertVM(v), '', 'revert');
  if (!run && !susp && !paused) actions.append(btn('開機', () => api('POST', `vm/${v.uuid}/start`), 'green', 'start'), revertBtn());
  if (susp || paused) actions.append(btn('恢復', () => api('POST', `vm/${v.uuid}/resume`), 'green', 'start'), revertBtn());
  if (run) actions.append(
    btn('關機(正常關機)', () => api('POST', `vm/${v.uuid}/stop`), '', 'stop'),
    btn('休眠', () => api('POST', `vm/${v.uuid}/suspend`), '', 'hibernate'),
    btn('暫停', () => api('POST', `vm/${v.uuid}/pause`), '', 'pause'),
    revertBtn(),
    btn('強制關機', async () => { if (!await dgConfirm('強制關機?', '「' + v.name + '」會被直接切斷電源,相當於拔插頭。', '強制關機', true)) throw CANCEL; await api('POST', `vm/${v.uuid}/kill`); }, 'danger', 'kill'));
  actions.append(btn('刪除', () => deleteVM(v), 'danger', 'del'));
  if (v.status === 'stopped' || run || susp) actions.append(btn('複製', () => cloneVM(v), '', 'clone'));
  return actions;
}
// 網卡(僅執行中的機器能拔掉/連回,這是 Parallels 的限制)
function partNics(v) {
  if (v.status !== 'running' || !v.nics || !v.nics.length) return el('div');
  const box = el('div', { className: 'sub' }, el('div', { className: 'sub-title' }, '網卡'));
  for (const n of v.nics) {
    const mac = (n.mac.match(/../g) || []).join(':');
    box.append(el('div', { className: 'row' },
      el('span', { className: 'net', textContent: n.kind }),
      el('div', { className: 'grow' }, n.connected ? '已連線' : '已拔掉', el('div', { className: 'note', textContent: mac })),
      n.connected
        ? btn('拔掉網卡', async () => {
            if (!await dgConfirm('拔掉網卡?', '拔掉「' + v.name + '」的 ' + n.kind + ' 網卡。如果你正透過這張網卡連線(例如 SSH),連線會中斷。', '拔掉', true)) throw CANCEL;
            await api('POST', `vm/${v.uuid}/nic/${n.name}/disconnect`);
          }, 'small danger', 'unplug')
        : btn('連回網卡', () => api('POST', `vm/${v.uuid}/nic/${n.name}/connect`), 'small green', 'plug')));
  }
  return box;
}
function fmtMem(mb) { return mb % 1024 === 0 ? (mb / 1024) + ' GB' : (mb / 1024).toFixed(1) + ' GB'; }
// 規格(CPU / 記憶體):展開即可看到;只有已關機的機器能修改(Parallels 的限制)
function partSpec(v) {
  const hw = v.hw, body = el('div', { className: 'body' });
  const box = el('details', { className: 'sub' }, el('summary', {}, el('span', { className: 'grow', textContent: '規格' }),
    el('small', { className: 'spec-line', textContent: hw ? hw.cpus + ' 核心 · ' + fmtMem(hw.memMB) : '' }), caret()), body);
  box.open = openSpecs.has(v.uuid);   // 預設收合;重畫時保留使用者展開的狀態
  box.addEventListener('toggle', () => { if (box.open) openSpecs.add(v.uuid); else openSpecs.delete(v.uuid); });
  if (!hw) { body.append(el('div', { className: 'empty', textContent: '(無法取得規格)' })); return box; }
  const stopped = v.status === 'stopped';
  const maxCpu = HOST.cpus || Math.max(hw.cpus, 1), maxMem = Math.max(Math.floor((HOST.memMB || hw.memMB) / 1024) * 1024, hw.memMB);
  const tickLeft = f => `calc(${f} * (100% - 18px) + 9px)`;
  // 滑桿只會停在「停靠點」:最小值,之後每個整數單位(核心數 / GB),最後是上限。
  // 滑桿本身以停靠點的序號(0..n)運作,所以不可能停在非整數的位置;
  // 機器目前的值若不在停靠點上(例如 3.5 GB),補一個停靠點,避免一打開就被改掉。
  const mk = (label, min, max, cur, fmt, unit) => {
    const vals = [min];
    for (let k = Math.floor(min / unit) + 1; k * unit <= max; k++) vals.push(k * unit);
    if (vals[vals.length - 1] !== max) vals.push(max);
    if (!vals.includes(cur)) { vals.push(cur); vals.sort((x, y) => x - y); }
    const n1 = vals.length - 1;
    const out = el('b', { textContent: fmt(cur) });
    const sl = el('input', { type: 'range', className: 'form-slider', min: 0, max: n1, step: 1, value: vals.indexOf(cur), disabled: !stopped });
    const fill = el('div', { className: 'slider-fill' });
    const wrap = el('div', { className: 'slider-wrap' }, fill, sl);
    const upd = () => wrap.style.setProperty('--sl-stop', `calc(${sl.value / n1} * (100% - 18px) + 9px)`);
    const res = { sl, get value() { return vals[+sl.value]; } };
    sl.addEventListener('input', () => { out.textContent = fmt(res.value); upd(); sync(); });
    upd();
    // 數字最多標 7 個且等距(間隔取能整除的最小值,讓最右邊的上限一定有數字)
    const ticks = el('div', { className: 'slider-ticklabels' + (stopped ? '' : ' dim') });
    let gap = 1; while (n1 / gap + 1 > 7 && gap < n1) gap++;
    while (n1 % gap !== 0 && gap < n1) gap++;
    if (gap === n1 && n1 > 6) gap = Math.ceil(n1 / 6);   // 沒有適合的整除間隔:退而求其次,最後一個一定標數字
    vals.forEach((t, i) => {
      const labeled = i === n1 || (i % gap === 0 && n1 - i >= gap / 2);   // 倒數第二個標籤太貼近上限就略過
      ticks.append(el('span', { textContent: labeled ? String(+(t / unit).toFixed(2)) : '', style: 'left:' + tickLeft(i / n1) }));
    });
    res.node = el('div', { className: 'spec-row' }, el('div', { className: 'spec-label' }, el('span', { textContent: label }), out), wrap, ticks);
    return res;
  };
  const cpu = mk('CPU 核心數', 1, maxCpu, hw.cpus, x => x + ' 核', 1);
  const mem = mk('記憶體(刻度單位:GB)', 512, maxMem, hw.memMB, fmtMem, 1024);
  const apply = btn('套用', async () => {
    await api('POST', `vm/${v.uuid}/spec`, { cpus: cpu.value, memMB: mem.value });
    msg('已更新「' + v.name + '」的規格');
  }, 'small primary');
  const sync = () => { apply.disabled = !stopped || (cpu.value === hw.cpus && mem.value === hw.memMB); };
  sync();
  body.append(cpu.node, mem.node);
  body.append(stopped ? el('div', { className: 'spec-actions' }, apply)
    : el('div', { className: 'empty', textContent: '需先關機才能修改規格' }));
  return box;
}
function partFw(v, mine) {
  const fw = el('div', { className: 'sub' }, el('div', { className: 'sub-title' }, '端口轉發', el('small', { textContent: 'Mac 埠 → VM 埠' })));
  if (!mine.length) fw.append(el('div', { className: 'empty', textContent: '(沒有規則)' }));
  for (const f of mine) fw.append(fwRow(f, 'VM'));
  fw.append(fwForm(v));
  return fw;
}
// 端口轉發區塊若因規則變動被重畫,保留使用者已展開、已輸入一半的新增表單
function carryForm(oldEl, newEl) {
  const of = oldEl.querySelector('form.fw'), nf = newEl.querySelector('form.fw');
  if (!of || !nf || of.hidden) return;
  nf.hidden = false;
  const tb = newEl.querySelector('.fw-add > button'); if (tb) tb.textContent = '－ 收起';
  const oi = of.querySelectorAll('select,input'), ni = nf.querySelectorAll('select,input');
  oi.forEach((x, i) => { if (ni[i]) ni[i].value = x.value; });
}

const PARTS = ['head', 'ips', 'actions', 'spec', 'nics', 'fw'];
const BUILD = { head: partHead, ips: partIps, actions: partActions, spec: partSpec, nics: partNics, fw: partFw };
function partSigs(v, forwards) {
  const mine = forwards.filter(f => norm(f.target) === norm(v.uuid));
  return { mine, sig: {
    head: v.name + '|' + v.status,
    ips: v.status + '|' + JSON.stringify(v.ips || null) + '|' + v.ip_configured,
    actions: v.status + '|' + v.name + '|' + v.uuid,
    spec: v.status + '|' + JSON.stringify(v.hw || null) + '|' + HOST.cpus + '|' + HOST.memMB,
    nics: v.status + '|' + v.name + '|' + JSON.stringify(v.nics || null),
    fw: v.uuid + '|' + JSON.stringify(mine) } };
}

let HOST = {};
const cards = new Map();   // uuid -> { node, parts, sigs, snap, snapBody }
function createCard(v, forwards) {
  const { mine, sig } = partSigs(v, forwards);
  const parts = {};
  for (const k of PARTS) parts[k] = BUILD[k](v, mine);
  const snap = snapSection(v);
  const node = el('details', { className: 'card' },
    el('summary', {}, parts.head),
    el('div', { className: 'vm-body' }, parts.ips, parts.actions, parts.spec, parts.nics, parts.fw, snap.node));
  node.open = openVMs.has(v.uuid);
  node.addEventListener('toggle', ev => {
    if (ev.target !== node) return;   // 忽略內層「快照」的 toggle
    if (node.open) openVMs.add(v.uuid); else openVMs.delete(v.uuid);
  });
  return { node, parts, sigs: sig, snap: snap.node, snapBody: snap.body };
}
function updateCard(e, v, forwards) {
  const { mine, sig } = partSigs(v, forwards);
  for (const k of PARTS) {
    if (e.sigs[k] === sig[k]) continue;   // 沒變就完全不碰
    const n = BUILD[k](v, mine);
    if (k === 'fw') carryForm(e.parts[k], n);
    e.parts[k].replaceWith(n);
    e.parts[k] = n; e.sigs[k] = sig[k];
  }
}

let otherSig = '';
function patch(s) {
  HOST = s.host || {};
  const host = $('vms');
  const seen = new Set();
  s.vms.forEach((v, idx) => {
    seen.add(v.uuid);
    let e = cards.get(v.uuid);
    if (!e) { e = createCard(v, s.forwards); cards.set(v.uuid, e); }
    else updateCard(e, v, s.forwards);
    if (host.children[idx] !== e.node) host.insertBefore(e.node, host.children[idx] || null);
  });
  for (const [id, e] of cards) if (!seen.has(id)) { e.node.remove(); cards.delete(id); }
  // 展開中的快照區塊:靜默更新(內容沒變就不動)
  for (const [id, e] of cards) if (e.snap.open) fillSnaps({ uuid: id }, e.snapBody);

  const known = new Set(s.vms.map(v => norm(v.uuid)));
  const rest = s.forwards.filter(f => !known.has(norm(f.target)));
  const sig = JSON.stringify(rest);
  if (sig !== otherSig) {
    otherSig = sig;
    const other = $('otherfw'); other.replaceChildren();
    if (rest.length) {
      const box = el('div', { className: 'card' }, el('div', { className: 'sub-title', textContent: '其他轉發(目標不是已知 VM)' }));
      for (const f of rest) box.append(fwRow(f, f.target));
      other.append(box);
    }
  }
}

// 同時只跑一個刷新;刷新途中又被要求刷新,就在這次結束後再跑一次
let loading = false, again = false;
async function load() {
  if (loading) { again = true; return; }
  loading = true;
  try {
    do { again = false; patch(await api('GET', 'state')); } while (again);
    rawApi('GET', 'session').then(x => { $('account').hidden = !x.authRequired; }).catch(() => {});
  } catch (e) { msg('錯誤: ' + e.message, true); }
  finally { loading = false; }
}
// 點擊畫面上任何地方都刷新一次(0.4 秒內連點只刷新一次)
let clickTimer;
document.addEventListener('click', () => { clearTimeout(clickTimer); clickTimer = setTimeout(load, 400); });

load();
// PWA:註冊 service worker(需要 secure context;失敗不影響一般使用)
if ('serviceWorker' in navigator && window.isSecureContext) navigator.serviceWorker.register('/sw.js').catch(() => {});
</script>
</body>
</html>
"""#
