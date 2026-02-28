const { contextBridge, ipcRenderer, shell } = require("electron");

const DEFAULT_DRAWER_URL = "http://127.0.0.1:17865/";
const DEFAULT_VIEWER_URL = "http://127.0.0.1:17866/";

function normalizeUrl(value, fallback) {
  const raw = (value || "").trim();
  if (!raw) return fallback;
  return raw.endsWith("/") ? raw : `${raw}/`;
}

const drawerUrl = normalizeUrl(process.env.WINDDRAWER_DRAWER_URL, DEFAULT_DRAWER_URL);
const viewerUrl = normalizeUrl(process.env.WINDDRAWER_VIEWER_URL, DEFAULT_VIEWER_URL);

contextBridge.exposeInMainWorld("winddrawerDesktop", {
  drawerUrl,
  viewerUrl,
  openExternal: (url) => shell.openExternal(url),
  onReloadAll: (handler) => {
    const wrapped = () => handler();
    ipcRenderer.on("winddrawer:reload-all", wrapped);
    return () => ipcRenderer.removeListener("winddrawer:reload-all", wrapped);
  },
});

