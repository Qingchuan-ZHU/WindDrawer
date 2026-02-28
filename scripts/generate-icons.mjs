import fs from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";
import sharp from "sharp";
import pngToIco from "png-to-ico";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, "..");

const svgPath = path.join(rootDir, "web", "static", "winddrawer-icon.svg");
const faviconPngPath = path.join(rootDir, "web", "static", "favicon.png");
const iconPngPath = path.join(rootDir, "build", "icon.png");
const iconIcoPath = path.join(rootDir, "build", "icon.ico");
const tempDir = path.join(rootDir, "build", ".icon-tmp");
const icoSizes = [16, 24, 32, 48, 64, 128, 256];

async function ensureDirs() {
  await fs.mkdir(path.dirname(faviconPngPath), { recursive: true });
  await fs.mkdir(path.dirname(iconPngPath), { recursive: true });
}

async function buildPngTargets() {
  await sharp(svgPath).resize(512, 512).png({ compressionLevel: 9 }).toFile(faviconPngPath);
  await sharp(svgPath).resize(512, 512).png({ compressionLevel: 9 }).toFile(iconPngPath);
}

async function buildIcoTarget() {
  await fs.rm(tempDir, { recursive: true, force: true });
  await fs.mkdir(tempDir, { recursive: true });

  const pngFiles = [];
  for (const size of icoSizes) {
    const target = path.join(tempDir, `icon-${size}.png`);
    await sharp(svgPath).resize(size, size).png({ compressionLevel: 9 }).toFile(target);
    pngFiles.push(target);
  }

  const icoBuffer = await pngToIco(pngFiles);
  await fs.writeFile(iconIcoPath, icoBuffer);
  await fs.rm(tempDir, { recursive: true, force: true });
}

async function main() {
  await ensureDirs();
  await buildPngTargets();
  await buildIcoTarget();
  console.log(`Generated icons from ${svgPath}`);
  console.log(`- ${faviconPngPath}`);
  console.log(`- ${iconPngPath}`);
  console.log(`- ${iconIcoPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
