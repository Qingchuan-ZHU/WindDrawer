async function fetchJSON(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

function el(id) {
  return document.getElementById(id);
}

function formatMetadata(meta) {
  if (!meta) return '';
  if (meta.zimage) return JSON.stringify(meta.zimage, null, 2);
  return JSON.stringify(meta, null, 2);
}

function setPreview(filename, url) {
  const preview = el('preview');
  preview.src = url + `?t=${Date.now()}`;
  el('openLink').href = url;
  const dl = el('downloadLink');
  dl.href = url;
  dl.download = filename;
}

async function loadMetadata(filename) {
  const metaPre = el('metaPre');
  metaPre.textContent = '加载中...';
  try {
    const res = await fetchJSON(`/api/metadata/${encodeURIComponent(filename)}`);
    metaPre.textContent = formatMetadata(res.metadata);
  } catch (err) {
    metaPre.textContent = `读取失败：${String(err)}`;
  }
}

async function loadOutputs() {
  const sel = el('fileSelect');
  sel.innerHTML = '';

  const res = await fetchJSON('/api/outputs');
  const items = res.items || [];

  for (const it of items) {
    const opt = document.createElement('option');
    opt.value = it.filename;
    opt.textContent = it.filename;
    opt.dataset.url = it.url;
    sel.appendChild(opt);
  }

  if (items.length > 0) {
    const first = items[0];
    setPreview(first.filename, first.url);
    await loadMetadata(first.filename);
  } else {
    el('preview').removeAttribute('src');
    el('metaPre').textContent = 'outputs/ 目录下暂无图片。';
  }
}

async function main() {
  el('refreshBtn').addEventListener('click', () => {
    loadOutputs().catch((err) => {
      el('metaPre').textContent = `刷新失败：${String(err)}`;
    });
  });

  el('fileSelect').addEventListener('change', async (e) => {
    const opt = e.target.selectedOptions[0];
    if (!opt) return;
    const filename = opt.value;
    const url = opt.dataset.url || `/outputs/${filename}`;
    setPreview(filename, url);
    await loadMetadata(filename);
  });

  await loadOutputs();
}

main().catch((err) => {
  el('metaPre').textContent = `初始化失败：${String(err)}`;
});
