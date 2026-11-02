// Electron main process (CommonJS). Owns the window, the application menu and the IPC
// bridge to the ESM DeviceManager (loaded via dynamic import). All device logic lives in
// device-manager.mjs / backends — this file is just wiring.
const { app, BrowserWindow, Menu, ipcMain, dialog, shell } = require('electron');
const path = require('node:path');
const fs = require('node:fs');
const { pathToFileURL } = require('node:url');

const WANT_MOCK = process.argv.includes('--mock') || !!process.env.SH2_MOCK;

let win = null;
let manager = null;

// Where the read-only libs (sh2-core, emulator, clients/linux) live.
function srcBase() {
  return app.isPackaged ? process.resourcesPath : path.resolve(__dirname, '..', '..', '..');
}

function emit(name, payload) {
  if (win && !win.isDestroyed()) win.webContents.send(`sh2:${name}`, payload);
}

async function initManager() {
  const mod = await import(pathToFileURL(path.join(__dirname, 'device-manager.mjs')).href);
  manager = new mod.DeviceManager({ srcBase: srcBase(), emit });
  await manager.setMode(WANT_MOCK ? 'mock' : 'ble');
}

function buildMenu() {
  const template = [
    {
      label: 'rehalo',
      submenu: [
        { role: 'reload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    },
    {
      label: 'Mode',
      submenu: [
        {
          id: 'mode-mock',
          label: 'Emulator (mock) — no hardware',
          type: 'radio',
          checked: !manager || manager.mode === 'mock',
          click: async () => { await manager.setMode('mock'); },
        },
        {
          id: 'mode-ble',
          label: 'Real BLE (BlueZ)',
          type: 'radio',
          checked: manager && manager.mode === 'ble',
          click: async () => { await manager.setMode('ble'); },
        },
      ],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// Set SH2_SMOKE=1 for a headless boot check: the window is created hidden and the app
// quits once the renderer has loaded (invisible in normal use).
const SMOKE = !!process.env.SH2_SMOKE;

function createWindow() {
  win = new BrowserWindow({
    width: 960,
    height: 760,
    minWidth: 720,
    minHeight: 560,
    show: !SMOKE,
    backgroundColor: '#0d1017',
    title: 'rehalo Desktop',
    autoHideMenuBar: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  if (SMOKE) {
    win.webContents.on('did-finish-load', async () => {
      console.log('SH2_SMOKE_OK mode=' + (manager ? manager.mode : '?'));
      try {
        // Drive the full flow through the real renderer->preload->ipcMain->manager path.
        const result = await win.webContents.executeJavaScript(`(async () => {
          const s = await window.sh2.scan(10);
          const dev = s.devices[0];
          const c = await window.sh2.connect(dev.id, dev.name);
          const r = await window.sh2.recover();
          const l = await window.sh2.frontLight(true);
          return { scanned: s.devices.length, connected: c.ok, pwLen: (r.password||'').length, lightOk: l.ok, lightRet: l.ret };
        })()`);
        console.log('SH2_SMOKE_FLOW ' + JSON.stringify(result));
      } catch (e) {
        console.log('SH2_SMOKE_FLOW_ERR ' + (e && e.message));
      }
      setTimeout(() => app.quit(), 200);
    });
    win.webContents.on('render-process-gone', (_e, d) => { console.log('SH2_SMOKE_RENDERER_GONE ' + JSON.stringify(d)); app.exit(1); });
  }
}

// ---- IPC: thin wrappers over the manager (which already returns {ok,...}) ----
function registerIpc() {
  const call = (fn) => async (_e, ...args) => {
    try { return await fn(...args); }
    catch (e) { return { ok: false, error: e.message }; }
  };
  ipcMain.handle('sh2:getState', call(async () => ({ ok: true, state: manager.snapshot() })));
  ipcMain.handle('sh2:setMode', call((m) => manager.setMode(m)));
  ipcMain.handle('sh2:scan', call((ms) => manager.scan(ms)));
  ipcMain.handle('sh2:connect', call((id, name) => manager.connect(id, name)));
  ipcMain.handle('sh2:authenticate', call((pw) => manager.authenticate(pw)));
  ipcMain.handle('sh2:recover', call((pw) => manager.recover(pw)));
  ipcMain.handle('sh2:frontLight', call((on) => manager.frontLight(on)));
  ipcMain.handle('sh2:setBrightness', call((v) => manager.setBrightness(v)));
  ipcMain.handle('sh2:alarm', call((a) => manager.alarm(a)));
  ipcMain.handle('sh2:deviceInfo', call(() => manager.deviceInfo()));
  ipcMain.handle('sh2:disconnect', call(() => manager.disconnect()));
  ipcMain.handle('sh2:savePassword', call(async (pw) => {
    if (!pw) return { ok: false, error: 'no password to save' };
    const { canceled, filePath } = await dialog.showSaveDialog(win, {
      title: 'Save SmartHalo 2 password',
      defaultPath: 'smarthalo2-password.txt',
      filters: [{ name: 'Text', extensions: ['txt'] }],
    });
    if (canceled || !filePath) return { ok: false, error: 'cancelled' };
    const body = `SmartHalo 2 device password (32 chars)\nGenerated: ${new Date().toISOString()}\n\n${pw}\n`;
    fs.writeFileSync(filePath, body, 'utf8');
    return { ok: true, path: filePath };
  }));
}

const smokeLog = (m) => { if (process.env.SH2_SMOKE) console.error('[smoke] ' + m); };

app.whenReady().then(async () => {
  smokeLog('ready');
  await initManager();
  smokeLog('manager initialized, mode=' + (manager && manager.mode));
  registerIpc();
  buildMenu();
  smokeLog('menu + ipc ready, creating window');
  createWindow();
  smokeLog('window created');
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
}).catch((e) => { console.error('[smoke] FATAL ' + (e && e.stack || e)); app.exit(2); });

app.on('window-all-closed', async () => {
  try { if (manager) { await manager.disconnect(); if (manager.backend) await manager.backend.teardown(); } } catch {}
  if (process.platform !== 'darwin') app.quit();
});
