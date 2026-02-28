const fs = require("fs");
const path = require("path");
const http = require("http");
const https = require("https");
const { spawn } = require("child_process");
const { app, BrowserWindow, shell, Menu, dialog } = require("electron");

const DEFAULT_DRAWER_URL = "http://127.0.0.1:17865/";
const DEFAULT_VIEWER_URL = "http://127.0.0.1:17866/";
const BACKEND_TIMEOUT_SEC = 180;

function normalizeUrl(value, fallback) {
  const raw = (value || "").trim();
  if (!raw) return fallback;
  return raw.endsWith("/") ? raw : `${raw}/`;
}

const DRAWER_URL = normalizeUrl(process.env.WINDDRAWER_DRAWER_URL, DEFAULT_DRAWER_URL);
const VIEWER_URL = normalizeUrl(process.env.WINDDRAWER_VIEWER_URL, DEFAULT_VIEWER_URL);

function toHealthUrl(baseUrl, pathSuffix) {
  return `${baseUrl.replace(/\/+$/, "")}${pathSuffix}`;
}

function isWindows() {
  return process.platform === "win32";
}

function isHttpReady(targetUrl, timeoutMs = 3000) {
  return new Promise((resolve) => {
    const url = new URL(targetUrl);
    const client = url.protocol === "https:" ? https : http;
    let settled = false;
    const finish = (ready) => {
      if (!settled) {
        settled = true;
        resolve(ready);
      }
    };

    const req = client.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port || undefined,
        path: url.pathname + url.search,
        method: "GET",
      },
      (res) => {
        res.resume();
        finish(res.statusCode >= 200 && res.statusCode < 500);
      },
    );

    req.on("error", () => finish(false));
    req.setTimeout(timeoutMs, () => {
      req.destroy();
      finish(false);
    });
    req.end();
  });
}

async function waitForHttpReady(targetUrl, timeoutSec = BACKEND_TIMEOUT_SEC) {
  const deadline = Date.now() + timeoutSec * 1000;
  while (Date.now() < deadline) {
    if (await isHttpReady(targetUrl)) {
      return true;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  return false;
}

function hasProjectFiles(rootDir) {
  if (!rootDir) return false;
  const required = isWindows() ? ["start.ps1", "docker-compose.yml", "Dockerfile"] : ["start.sh", "docker-compose.yml", "Dockerfile"];
  return required.every((name) => fs.existsSync(path.join(rootDir, name)));
}

function dedupePaths(paths) {
  const seen = new Set();
  const result = [];
  for (const item of paths) {
    if (!item) continue;
    const normalized = path.resolve(item);
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    result.push(normalized);
  }
  return result;
}

function resolveDevProjectRoot() {
  const candidates = dedupePaths([
    process.env.WINDDRAWER_PROJECT_ROOT,
    process.cwd(),
    path.resolve(__dirname, ".."),
  ]);
  return candidates.find((root) => hasProjectFiles(root)) || null;
}

function syncRuntimeTemplateToUserData() {
  const templateRoot = path.join(process.resourcesPath, "runtime-template");
  if (!hasProjectFiles(templateRoot)) {
    return null;
  }

  const runtimeRoot = path.join(app.getPath("userData"), "runtime");
  const markerPath = path.join(runtimeRoot, ".runtime-version");
  const expectedVersion = app.getVersion();
  const currentVersion = fs.existsSync(markerPath) ? fs.readFileSync(markerPath, "utf8").trim() : "";

  if (!hasProjectFiles(runtimeRoot) || currentVersion !== expectedVersion) {
    fs.mkdirSync(runtimeRoot, { recursive: true });
    fs.cpSync(templateRoot, runtimeRoot, { recursive: true, force: true });
    fs.writeFileSync(markerPath, `${expectedVersion}\n`, "utf8");
  }

  return runtimeRoot;
}

function resolveBackendRoot() {
  const envRoot = process.env.WINDDRAWER_PROJECT_ROOT ? path.resolve(process.env.WINDDRAWER_PROJECT_ROOT) : null;
  if (hasProjectFiles(envRoot)) {
    return envRoot;
  }

  if (!app.isPackaged) {
    return resolveDevProjectRoot();
  }

  const cwdRoot = hasProjectFiles(process.cwd()) ? path.resolve(process.cwd()) : null;
  if (cwdRoot) {
    return cwdRoot;
  }

  return syncRuntimeTemplateToUserData();
}

function runCommand(command, args, cwd) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env: process.env,
      stdio: "inherit",
      windowsHide: false,
    });

    child.on("error", (error) => reject(error));
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with code ${code}`));
      }
    });
  });
}

async function startBackend(rootDir) {
  if (isWindows()) {
    const scriptPath = path.join(rootDir, "start.ps1");
    const attempts = [
      ["pwsh", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath, "-NoOpenBrowser"]],
      ["powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath, "-NoOpenBrowser"]],
    ];
    const errors = [];

    for (const [command, args] of attempts) {
      try {
        await runCommand(command, args, rootDir);
        return;
      } catch (error) {
        errors.push(`${command}: ${error.message}`);
      }
    }

    throw new Error(`Failed to run backend bootstrap.\n${errors.join("\n")}`);
  }

  const scriptPath = path.join(rootDir, "start.sh");
  await runCommand("bash", [scriptPath], rootDir);
}

async function ensureBackendReady() {
  const drawerHealthUrl = toHealthUrl(DRAWER_URL, "/api/models");
  const viewerHealthUrl = toHealthUrl(VIEWER_URL, "/api/images");
  const drawerReady = await isHttpReady(drawerHealthUrl);
  const viewerReady = await isHttpReady(viewerHealthUrl);
  if (drawerReady && viewerReady) {
    return;
  }

  const usingDefaultUrls = DRAWER_URL === DEFAULT_DRAWER_URL && VIEWER_URL === DEFAULT_VIEWER_URL;
  if (!usingDefaultUrls) {
    throw new Error(`Configured URLs are not reachable.\nDrawer: ${drawerHealthUrl}\nViewer: ${viewerHealthUrl}`);
  }

  const backendRoot = resolveBackendRoot();
  if (!backendRoot) {
    throw new Error(
      [
        "Cannot locate WindDrawer backend files.",
        "Set WINDDRAWER_PROJECT_ROOT to your WindDrawer repository path, or start backend manually with start.ps1.",
      ].join("\n"),
    );
  }

  await startBackend(backendRoot);

  const drawerOk = await waitForHttpReady(drawerHealthUrl, BACKEND_TIMEOUT_SEC);
  const viewerOk = await waitForHttpReady(viewerHealthUrl, BACKEND_TIMEOUT_SEC);
  if (!drawerOk || !viewerOk) {
    throw new Error(`Backend startup timed out.\nDrawer: ${drawerHealthUrl}\nViewer: ${viewerHealthUrl}`);
  }
}

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
  ensureBackendReady()
    .catch((error) => {
      dialog.showErrorBox(
        "WindDrawer Backend Startup Failed",
        `${error.message}\n\nYou can start backend manually, then click Reload All.`,
      );
    })
    .finally(() => {
      const mainWindow = createMainWindow();
      createMenu(mainWindow);

      app.on("activate", () => {
        if (BrowserWindow.getAllWindows().length === 0) {
          const win = createMainWindow();
          createMenu(win);
        }
      });
    });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
