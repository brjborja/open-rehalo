// Preload (CommonJS, sandboxed). Exposes a minimal, explicit API to the renderer over
// contextBridge — no Node, no ipcRenderer leak.
const { contextBridge, ipcRenderer } = require('electron');

const EVENTS = ['sh2:log', 'sh2:status', 'sh2:device'];

contextBridge.exposeInMainWorld('sh2', {
  getState: () => ipcRenderer.invoke('sh2:getState'),
  setMode: (mode) => ipcRenderer.invoke('sh2:setMode', mode),
  scan: (durationMs) => ipcRenderer.invoke('sh2:scan', durationMs),
  connect: (id, name) => ipcRenderer.invoke('sh2:connect', id, name),
  authenticate: (password) => ipcRenderer.invoke('sh2:authenticate', password),
  recover: (newPassword) => ipcRenderer.invoke('sh2:recover', newPassword),
  frontLight: (on) => ipcRenderer.invoke('sh2:frontLight', on),
  setBrightness: (v) => ipcRenderer.invoke('sh2:setBrightness', v),
  alarm: (action) => ipcRenderer.invoke('sh2:alarm', action),
  deviceInfo: () => ipcRenderer.invoke('sh2:deviceInfo'),
  disconnect: () => ipcRenderer.invoke('sh2:disconnect'),
  savePassword: (pw) => ipcRenderer.invoke('sh2:savePassword', pw),
  on: (channel, cb) => {
    if (!EVENTS.includes(channel)) return () => {};
    const listener = (_e, data) => cb(data);
    ipcRenderer.on(channel, listener);
    return () => ipcRenderer.removeListener(channel, listener);
  },
});
