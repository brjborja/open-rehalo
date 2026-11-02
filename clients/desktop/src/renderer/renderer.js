// Renderer — pure DOM, no Node. Talks to the main process only through window.sh2.
const $ = (id) => document.getElementById(id);
const api = window.sh2;

let currentPassword = null;

// ---------- logging ----------
function addLog({ msg, level = 'info', t }) {
  const el = document.createElement('div');
  el.className = `l ${level}`;
  const time = new Date(t || Date.now()).toLocaleTimeString();
  el.innerHTML = `<span class="t">${time}</span>`;
  el.appendChild(document.createTextNode(msg));
  const log = $('log');
  log.appendChild(el);
  log.scrollTop = log.scrollHeight;
}

// ---------- state rendering ----------
function applyState(s) {
  if (!s) return;
  // mode segmented control
  $('modeMock').classList.toggle('active', s.mode === 'mock');
  $('modeBle').classList.toggle('active', s.mode === 'ble');

  // connection pill + dot
  const pill = $('connPill');
  pill.textContent = s.connected ? `Connected: ${s.connectedName}` : 'Disconnected';
  pill.classList.toggle('ok', s.connected);
  $('statusDot').classList.toggle('on', s.connected);

  // pairing availability
  $('recoverBtn').disabled = !s.connected;
  $('authBtn').disabled = !s.connected;

  // controls lock
  const fs = $('controlsFs');
  fs.disabled = !s.authed;
  $('lockBadge').textContent = s.authed ? 'unlocked' : 'locked';
  $('lockBadge').classList.toggle('open', s.authed);

  // light visual
  const halo = $('halo');
  halo.classList.toggle('on', !!(s.light && s.light.on));
  halo.classList.toggle('off', !(s.light && s.light.on));
  $('haloLabel').textContent = (s.light && s.light.on) ? 'light on' : 'light off';
  if (s.light) {
    halo.style.setProperty('--glow', (s.light.brightness / 255).toFixed(2));
    $('lightToggle').checked = !!s.light.on;
    $('brightness').value = s.light.brightness;
    $('brightVal').textContent = s.light.brightness;
  }

  // password box
  if (s.password) {
    currentPassword = s.password;
    $('pwValue').textContent = s.password;
    $('pwBox').classList.remove('hidden');
  }
}

// ---------- device list ----------
function clearDevices() { $('deviceList').innerHTML = ''; }
function addDevice(d) {
  const list = $('deviceList');
  const empty = list.querySelector('.empty');
  if (empty) empty.remove();
  if (list.querySelector(`[data-id="${CSS.escape(d.id)}"]`)) return;
  const li = document.createElement('li');
  li.dataset.id = d.id;
  li.innerHTML = `<span><span class="dev-name">${d.name}</span>
      ${d.isHalo ? '<span class="dev-halo"> ● SmartHalo</span>' : ''}
      <br><span class="dev-addr">${d.address || d.id}</span></span>`;
  const btn = document.createElement('button');
  btn.className = 'btn small';
  btn.textContent = 'Connect';
  btn.onclick = async () => {
    btn.disabled = true; btn.textContent = 'Connecting…';
    const r = await api.connect(d.id, d.name);
    btn.disabled = false; btn.textContent = r.ok ? 'Connected' : 'Retry';
  };
  li.appendChild(btn);
  list.appendChild(li);
}

// ---------- wiring ----------
$('modeMock').onclick = () => api.setMode('mock');
$('modeBle').onclick = () => api.setMode('ble');

$('scanBtn').onclick = async () => {
  clearDevices();
  $('deviceList').innerHTML = '<li class="empty">Scanning…</li>';
  $('scanBtn').disabled = true;
  const r = await api.scan(8000);
  $('scanBtn').disabled = false;
  if (!r.ok || !r.devices || r.devices.length === 0) {
    $('deviceList').innerHTML = `<li class="empty">${r.error ? 'Error: ' + r.error : 'Nothing found.'}</li>`;
  }
};

$('recoverBtn').onclick = async () => {
  $('recoverBtn').disabled = true;
  await api.recover();
  $('recoverBtn').disabled = false;
};

$('authBtn').onclick = async () => {
  const pw = $('existingPw').value.trim();
  await api.authenticate(pw);
};

$('copyPwBtn').onclick = async () => {
  if (currentPassword) { try { await navigator.clipboard.writeText(currentPassword); addLog({ msg: 'Password copied to the clipboard.' }); } catch {} }
};
$('savePwBtn').onclick = async () => {
  const r = await api.savePassword(currentPassword);
  if (r.ok) addLog({ msg: 'Password saved to ' + r.path });
};

$('lightToggle').onchange = (e) => api.frontLight(e.target.checked);
let brTimer = null;
$('brightness').oninput = (e) => {
  $('brightVal').textContent = e.target.value;
  clearTimeout(brTimer);
  brTimer = setTimeout(() => api.setBrightness(Number(e.target.value)), 120);
};
$('alarmArm').onclick = () => api.alarm('arm');
$('alarmDisarm').onclick = () => api.alarm('disarm');
$('alarmReport').onclick = () => api.alarm('report');
$('infoBtn').onclick = async () => {
  const r = await api.deviceInfo();
  const out = $('infoOut');
  out.classList.remove('hidden');
  out.textContent = r.ok ? JSON.stringify(r.info, null, 2) : 'Error: ' + r.error;
};
$('disconnectBtn').onclick = () => api.disconnect();
$('clearLog').onclick = () => { $('log').innerHTML = ''; };

// ---------- events from main ----------
api.on('sh2:log', addLog);
api.on('sh2:status', applyState);
api.on('sh2:device', addDevice);

// ---------- init ----------
(async () => {
  const r = await api.getState();
  if (r && r.ok) applyState(r.state);
  addLog({ msg: 'Interface ready. Choose a mode and press "Scan".' });
})();
