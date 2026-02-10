async function fetchJSON(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

function el(id) {
  return document.getElementById(id);
}

let currentJobId = null;
let currentEventSource = null;

function toast(msg, detail) {
  const t = document.createElement('div');
  t.className = 'toast';
  t.innerHTML = `<div>${msg}</div>${detail ? `<div class="small">${detail}</div>` : ''}`;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 3500);
}

function appendLog(line) {
  const log = el('log');
  log.textContent += line + "\n";
  log.scrollTop = log.scrollHeight;
}

function clearLog() {
  el('log').textContent = '';
}

function clearGallery() {
  el('gallery').innerHTML = '';
}

function addImageCard(item) {
  const card = document.createElement('div');
  card.className = 'card';

  const meta = document.createElement('div');
  meta.className = 'meta';
  meta.textContent = `No. ${item.idx + 1}/${item.batch_size} | Seed ${item.seed} | ${item.width}x${item.height}`;

  const img = document.createElement('img');
  img.src = item.url + `?t=${Date.now()}`;
  img.loading = 'lazy';

  const actions = document.createElement('div');
  actions.className = 'actions';

  const open = document.createElement('a');
  open.href = item.url;
  open.target = '_blank';
  open.rel = 'noopener';
  open.textContent = 'Open / 打开';

  const dl = document.createElement('a');
  dl.href = item.url;
  dl.download = item.filename;
  dl.textContent = 'Download / 下载';

  actions.appendChild(open);
  actions.appendChild(dl);

  card.appendChild(meta);
  card.appendChild(img);
  card.appendChild(actions);

  el('gallery').appendChild(card);
}

async function loadOptions() {
  const aspects = await fetchJSON('/api/aspects');
  const aspectSel = el('aspect');
  aspectSel.innerHTML = '';
  for (const a of aspects.aspects) {
    const opt = document.createElement('option');
    opt.value = JSON.stringify({ w: a.w, h: a.h });
    opt.textContent = a.label;
    aspectSel.appendChild(opt);
  }

  const models = await fetchJSON('/api/models');
  const modelSel = el('model');
  modelSel.innerHTML = '';
  for (const m of models.models) {
    const opt = document.createElement('option');
    opt.value = m;
    opt.textContent = m;
    modelSel.appendChild(opt);
  }
}

function setBusy(busy) {
  el('renderBtn').disabled = busy;
  el('stopBtn').disabled = !busy;
}

async function startRender() {
  const aspect = JSON.parse(el('aspect').value);
  const payload = {
    prompt: el('prompt').value,
    width: aspect.w,
    height: aspect.h,
    steps: Number(el('steps').value || 8),
    batch_size: Number(el('batch').value || 1),
    seed: Number(el('seed').value || 42),
    auto_random_seed: el('autoSeed').checked,
    sd_model: el('model').value,
  };

  clearLog();
  clearGallery();
  setBusy(true);

  const res = await fetch('/api/render', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    setBusy(false);
    throw new Error(await res.text());
  }

  const { job_id } = await res.json();
  appendLog(`Job: ${job_id}`);

  currentJobId = job_id;

  const es = new EventSource(`/api/events/${job_id}`);
  currentEventSource = es;

  es.addEventListener('hello', (e) => {
    // noop
  });

  es.addEventListener('job_started', () => {
    toast('Start Rendering / 开始渲染');
  });

  es.addEventListener('render_start', (e) => {
    const d = JSON.parse(e.data);
    toast(`Processing ${d.idx + 1}/${d.batch_size}...`, `${d.width}x${d.height} | seed ${d.seed}`);
  });

  es.addEventListener('log', (e) => {
    const d = JSON.parse(e.data);
    appendLog(d.line);
  });

  es.addEventListener('image', (e) => {
    const d = JSON.parse(e.data);
    addImageCard(d);
  });

  es.addEventListener('job_stopping', () => {
    toast('Stopping... / 正在停止');
  });

  es.addEventListener('job_cancelled', () => {
    toast('Cancelled / 已取消');
    es.close();
    currentEventSource = null;
    currentJobId = null;
    setBusy(false);
  });

  es.addEventListener('job_error', (e) => {
    const d = JSON.parse(e.data);
    appendLog(`ERROR: ${d.message}`);
    toast('Error / 失败', d.message);
    es.close();
    currentEventSource = null;
    currentJobId = null;
    setBusy(false);
  });

  es.addEventListener('job_done', () => {
    toast('Done / 完成');
    es.close();
    currentEventSource = null;
    currentJobId = null;
    setBusy(false);
  });

  es.onerror = () => {
    // network issues, server restart, etc.
  };
}

async function stopRender() {
  if (!currentJobId) return;
  try {
    await fetch(`/api/render/${currentJobId}/stop`, { method: 'POST' });
    toast('Stop Signal Sent / 已发送停止指令');
  } catch (err) {
    toast('Action Failed / 操作失败', String(err));
  }
}

async function main() {
  await loadOptions();
  el('renderBtn').addEventListener('click', () => {
    startRender().catch((err) => {
      toast('Request Failed / 请求失败', String(err));
      currentJobId = null;
      if (currentEventSource) {
        currentEventSource.close();
        currentEventSource = null;
      }
      setBusy(false);
    });
  });
  el('stopBtn').addEventListener('click', () => {
    stopRender();
  });
  el('randomSeedBtn').addEventListener('click', () => {
    el('seed').value = Math.floor(Math.random() * 4294967296);
  });
}

main().catch((err) => {
  toast('Init Failed / 初始化失败', String(err));
});
