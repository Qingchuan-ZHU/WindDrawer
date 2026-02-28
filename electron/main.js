const path = require("path");
const { app, BrowserWindow, shell, Menu } = require("electron");

const DEFAULT_DRAWER_URL = "http://127.0.0.1:17865/";
const DEFAULT_VIEWER_URL = "http://127.0.0.1:17866/";

function normalizeUrl(value, fallback) {
  const raw = (value || "").trim();
  if (!raw) return fallback;
  return raw.endsWith("/") ? raw : `${raw}/`;
}

const DRAWER_URL = normalizeUrl(process.env.WINDDRAWER_DRAWER_URL, DEFAULT_DRAWER_URL);
const VIEWER_URL = normalizeUrl(process.env.WINDDRAWER_VIEWER_URL, DEFAULT_VIEWER_URL);

function createMainWindow() {
  const iconPath = path.join(__dirname, "..", "web", "static", "favicon.png");
  const preloadPath = path.join(__dirname, "preload.js");

  const mainWindow = new BrowserWindow({
    width: 1680,
    height: 980,
    minWidth: 1200,
    minHeight: 720,
    icon: iconPath,
    title: "WindDrawer Desktop",
    webPreferences: {
      preload: preloadPath,
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: "deny" };
  });

  mainWindow.loadFile(path.join(__dirname, "shell.html"));
  return mainWindow;
}

function createMenu(mainWindow) {
  const template = [
    {
      label: "WindDrawer",
      submenu: [
        {
          label: "Reload Panels",
          accelerator: "CmdOrCtrl+R",
          click: () => {
            mainWindow.webContents.send("winddrawer:reload-all");
          },
        },
        {
          label: "Open Drawer In Browser",
          click: () => shell.openExternal(DRAWER_URL),
        },
        {
          label: "Open Viewer In Browser",
          click: () => shell.openExternal(VIEWER_URL),
        },
        { type: "separator" },
        { role: "quit" },
      ],
    },
    {
      label: "View",
      submenu: [{ role: "toggledevtools" }, { role: "resetzoom" }, { role: "zoomin" }, { role: "zoomout" }],
    },
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

app.whenReady().then(() => {
  const mainWindow = createMainWindow();
  createMenu(mainWindow);

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      const win = createMainWindow();
      createMenu(win);
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

