import * as E from "./engine.js";
const m = E.mupdf;
const $ = (s) => document.querySelector(s);
const S = { doc: null, name: "document.pdf", pw: "", zoom: 1.3, tool: "view", cur: 0, dirty: false, handle: null, sizes: [] };
window.__S = S; window.__E = E; // test hooks
const status = (t) => { $("#st").textContent = t; };
const dpr = () => Math.min(window.devicePixelRatio || 1, 2);

// ---------- file io ----------
async function pickFiles(multiple) {
  if (window.showOpenFilePicker) {
    try { const hs = await showOpenFilePicker({ multiple, types: [{ description: "PDF", accept: { "application/pdf": [".pdf"] } }] });
      return Promise.all(hs.map(async h => ({ name: h.name, handle: h, bytes: new Uint8Array(await (await h.getFile()).arrayBuffer()) }))); } catch { return []; }
  }
  return new Promise(res => { const i = $("#fileIn"); i.multiple = multiple; i.value = ""; i.onchange = async () => res(await Promise.all([...i.files].map(async f => ({ name: f.name, bytes: new Uint8Array(await f.arrayBuffer()) })))); i.click(); });
}
async function writeOut(name, bytes, handle) {
  if (handle) { try { const w = await handle.createWritable(); await w.write(bytes); await w.close(); return handle; } catch { } }
  if (window.showSaveFilePicker) { try { const h = await showSaveFilePicker({ suggestedName: name, types: [{ description: "PDF", accept: { "application/pdf": [".pdf"] } }] }); const w = await h.createWritable(); await w.write(bytes); await w.close(); return h; } catch (e) { if (e.name === "AbortError") return null; } }
  const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([bytes], { type: "application/pdf" })); a.download = name; document.body.appendChild(a); a.click(); a.remove(); return null;
}
function askDialog(title, fields, okText = "OK") {
  return new Promise(res => {
    const d = $("#dlg"), f = $("#dform");
    f.innerHTML = `<b>${title}</b>` + fields.map(x => x.type === "select"
      ? `<label>${x.label}</label><select name="${x.name}">${x.options.map(o => `<option value="${o[0]}">${o[1]}</option>`).join("")}</select>`
      : x.type === "note" ? `<div style="margin-top:8px;color:#9aa0a6">${x.label}</div>`
      : `<label>${x.label}</label><input name="${x.name}" type="${x.type || "text"}" value="${x.value ?? ""}" ${x.type === "file" ? 'accept="' + (x.accept || "") + '"' : ""}>`).join("")
      + `<menu><button value="cancel" formnovalidate>Cancel</button><button value="ok" id="dok">${okText}</button></menu>`;
    d.onclose = () => { if (d.returnValue !== "ok") return res(null); const o = {}; for (const x of fields) { if (x.type === "note") continue; const el = f.elements[x.name]; o[x.name] = x.type === "file" ? el.files[0] : el.value; } res(o); };
    d.returnValue = ""; d.showModal();
  });
}

// ---------- document lifecycle ----------
async function openBytes(bytes, name, handle) {
  let pw = "";
  for (;;) {
    try { S.doc = E.open(bytes, pw); break; }
    catch (e) { if (e.code !== "PASSWORD") { alert("Cannot open: " + e.message); return; }
      const r = await askDialog("Password required", [{ name: "pw", label: "Password", type: "password" }]); if (!r) return; pw = r.pw; }
  }
  S.name = name; S.handle = handle || null; S.pw = pw; S.cur = 0; S.dirty = false;
  try { S.doc.enableJournal(); } catch { }
  try { S.doc.enableJS(); } catch { }
  chat.length = 0; $("#chat").innerHTML = "";
  await buildAll(); updBtns(); status(`Opened ${name} (${S.doc.countPages()} pages)`);
}
function updBtns() {
  const on = !!S.doc; for (const id of ["bSave", "bSaveAs"]) $("#" + id).disabled = !on;
  let u = false, r = false; try { u = on && S.doc.canUndo(); r = on && S.doc.canRedo(); } catch { }
  $("#bUndo").disabled = !u; $("#bRedo").disabled = !r;
}
function op(name, fn) {
  const d = S.doc; try { d.beginOperation(name); } catch { }
  try { const r = fn(); try { d.endOperation(); } catch { } S.dirty = true; updBtns(); return r; }
  catch (e) { try { d.abandonOperation(); } catch { } throw e; }
}
async function buildAll() {
  const host = $("#docs"); host.innerHTML = ""; S.sizes = []; const n = S.doc.countPages();
  const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting && !e.target.dataset.done) { e.target.dataset.done = 1; renderPage(+e.target.dataset.i); } }), { root: host, rootMargin: "400px" });
  S.io = io;
  for (let i = 0; i < n; i++) {
    const sz = E.pageSize(S.doc, i); S.sizes.push(sz);
    const d = document.createElement("div"); d.className = "pg"; d.dataset.i = i; d.id = "pg" + i;
    d.style.width = sz.w * S.zoom + "px"; d.style.height = sz.h * S.zoom + "px";
    d.innerHTML = `<img alt=""><div class="ov"></div>`; host.appendChild(d); io.observe(d); attachOverlay(d, i);
  }
  buildThumbs();
}
let renderTok = {};
function renderPage(i) {
  const d = $("#pg" + i); if (!d || !S.doc) return;
  const sc = S.zoom * dpr();
  const sz = E.pageSize(S.doc, i); S.sizes[i] = sz; d.style.width = sz.w * S.zoom + "px"; d.style.height = sz.h * S.zoom + "px";
  const png = E.renderPNG(S.doc, i, sc);
  const img = d.querySelector("img"); const old = img.src; img.src = URL.createObjectURL(new Blob([png], { type: "image/png" })); if (old.startsWith("blob:")) URL.revokeObjectURL(old);
  drawWidgets(d, i);
}
function refreshPage(i) { renderPage(i); thumb(i); }
function drawWidgets(d, i) {
  d.querySelectorAll(".wd").forEach(e => e.remove());
  if (S.tool !== "view") return;
  let ws = []; try { ws = E.listWidgets(S.doc, i); } catch { }
  for (const w of ws) {
    if (w.readOnly || !["text", "checkbox", "radiobutton", "combobox", "listbox"].includes(w.type)) continue;
    const [x0, y0, x1, y1] = w.rect, sz = S.sizes[i];
    let el;
    if (w.type === "text") { el = document.createElement("input"); el.value = w.value || ""; el.onchange = () => { op("form", () => E.setWidget(S.doc, i, w.idx, el.value)); thumb(i); }; }
    else if (w.type === "checkbox" || w.type === "radiobutton") { el = document.createElement("input"); el.type = "checkbox"; el.checked = !!w.value && w.value !== "Off"; el.onchange = () => { op("form", () => E.setWidget(S.doc, i, w.idx, el.checked)); refreshPage(i); }; }
    else { el = document.createElement("select"); for (const o of w.options) el.add(new Option(o, o)); el.value = w.value; el.onchange = () => { op("form", () => E.setWidget(S.doc, i, w.idx, el.value)); thumb(i); }; }
    el.className = "wd"; Object.assign(el.style, { left: (x0 - sz.x) * S.zoom + "px", top: (y0 - sz.y) * S.zoom + "px", width: (x1 - x0) * S.zoom + "px", height: (y1 - y0) * S.zoom + "px" });
    d.appendChild(el);
  }
}
function buildThumbs() {
  const t = $("#thumbs"); t.innerHTML = ""; const n = S.doc.countPages();
  for (let i = 0; i < n; i++) {
    const e = document.createElement("div"); e.className = "th" + (i === S.cur ? " cur" : ""); e.dataset.i = i; e.draggable = true;
    e.innerHTML = `<img alt=""><div class="n">${i + 1}</div><div class="tb"><button title="Rotate">⟳</button><button title="Delete">✕</button></div>`;
    e.onclick = (ev) => { if (ev.target.closest("button")) return; S.cur = i; $("#pg" + i).scrollIntoView(); markCur(); };
    const [bR, bD] = e.querySelectorAll("button");
    bR.onclick = () => { op("rotate", () => E.rotatePage(S.doc, i, 90)); refreshPage(i); };
    bD.onclick = async () => { if (S.doc.countPages() < 2) return alert("Cannot delete the only page"); op("delete page", () => S.doc.deletePage(i)); S.cur = Math.min(S.cur, S.doc.countPages() - 1); await buildAll(); };
    e.ondragstart = (ev) => ev.dataTransfer.setData("text/pg", String(i));
    e.ondragover = (ev) => ev.preventDefault();
    e.ondrop = async (ev) => { ev.preventDefault(); const from = +ev.dataTransfer.getData("text/pg"); if (isNaN(from) || from === i) return; const order = [...Array(n).keys()].filter(k => k !== from); order.splice(i, 0, from); op("reorder", () => E.reorder(S.doc, order)); S.cur = i; await buildAll(); };
    t.appendChild(e); thumb(i);
  }
}
function thumb(i) { const e = $(`.th[data-i="${i}"] img`); if (!e || !S.doc) return; e.src = URL.createObjectURL(new Blob([E.renderPNG(S.doc, i, 0.3)], { type: "image/png" })); }
function markCur() { document.querySelectorAll(".th").forEach(e => e.classList.toggle("cur", +e.dataset.i === S.cur)); $("#pgno").textContent = S.doc ? `Page ${S.cur + 1} / ${S.doc.countPages()}` : ""; }
$("#docs").addEventListener("scroll", () => { if (!S.doc) return; const h = $("#docs"), mid = h.scrollTop + h.clientHeight / 3; for (const p of h.querySelectorAll(".pg")) { if (p.offsetTop + p.offsetHeight > mid) { const i = +p.dataset.i; if (i !== S.cur) { S.cur = i; markCur(); } break; } } });

// ---------- annotation / selection overlay ----------
function attachOverlay(pg, i) {
  const ov = pg.querySelector(".ov"); let start = null, box = null, pts = null;
  const pos = (ev) => { const r = pg.getBoundingClientRect(); const sz = S.sizes[i]; return [(ev.clientX - r.left) / S.zoom + sz.x, (ev.clientY - r.top) / S.zoom + sz.y]; };
  const css = (a, b) => ({ left: Math.min(a[0], b[0]) - S.sizes[i].x, top: Math.min(a[1], b[1]) - S.sizes[i].y, w: Math.abs(a[0] - b[0]), h: Math.abs(a[1] - b[1]) });
  ov.onpointerdown = (ev) => { if (S.tool === "view" && !ev.shiftKey && ev.target.closest(".wd")) return; if (S.doc == null) return; S.cur = i; markCur(); start = pos(ev); ov.setPointerCapture(ev.pointerId); pts = [start];
    box = document.createElement("div"); box.className = "sel"; ov.appendChild(box); };
  ov.onpointermove = (ev) => { if (!start) return; const p = pos(ev); pts.push(p); const c = css(start, p);
    Object.assign(box.style, S.tool === "Line" || S.tool === "Ink" ? { display: "none" } : { left: c.left * S.zoom + "px", top: c.top * S.zoom + "px", width: c.w * S.zoom + "px", height: c.h * S.zoom + "px", display: "block" }); };
  ov.onpointerup = async (ev) => {
    if (!start) return; const a = start, b = pos(ev); start = null; box.remove(); const t = S.tool; const col = $("#color").value;
    const rect = [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[0], b[0]), Math.max(a[1], b[1])];
    const tiny = Math.abs(a[0] - b[0]) < 3 && Math.abs(a[1] - b[1]) < 3;
    try {
      if (t === "view") { if (!tiny) { const txt = E.selectionText(S.doc, i, a, b); if (txt) { try { await navigator.clipboard.writeText(txt); status("Copied " + txt.length + " characters"); } catch { status("Selected text: " + txt.slice(0, 80)); } } } return; }
      if (["Highlight", "Underline", "StrikeOut"].includes(t)) { if (tiny) return; const q = E.selectionQuads(S.doc, i, a, b); if (!q.length) return status("No text under selection"); op("markup", () => E.addMarkup(S.doc, i, t, q, col)); }
      else if (t === "Ink") { if (pts.length < 2) return; op("ink", () => E.addInk(S.doc, i, [pts], col, 2)); }
      else if (t === "Line") { if (tiny) return; op("line", () => E.addLine(S.doc, i, a, b, col, 2)); }
      else if (t === "Square") { if (tiny) return; op("box", () => E.addShape(S.doc, i, "Square", rect, col, 2)); }
      else if (t === "Redact") { if (tiny) return; op("mark redaction", () => E.redactRects(S.doc, i, [rect])); status("Redaction marked (not applied until you press Apply redactions)"); }
      else if (t === "Text") { const r = await askDialog("Note", [{ name: "t", label: "Text" }]); if (!r || !r.t) return; op("note", () => E.addNote(S.doc, i, a, r.t)); }
      else if (t === "FreeText") { const r = await askDialog("Text box", [{ name: "t", label: "Text" }, { name: "s", label: "Size", value: 12 }]); if (!r || !r.t) return; const w = tiny ? 200 : rect[2] - rect[0], h = tiny ? 30 : rect[3] - rect[1]; op("text", () => E.addFreeText(S.doc, i, [a[0], a[1], a[0] + w, a[1] + Math.max(h, +r.s * 1.6)], r.t, +r.s || 12, col)); }
    } catch (e) { alert(e.message); }
    refreshPage(i);
  };
  ov.ondblclick = (ev) => { // delete annotation under pointer
    if (S.tool !== "view") return; const p = pos(ev); const an = E.listAnnots(S.doc, i);
    for (let k = an.length - 1; k >= 0; k--) { const r = an[k].rect; if (p[0] >= r[0] && p[0] <= r[2] && p[1] >= r[1] && p[1] <= r[3] && an[k].type !== "Widget") { if (confirm("Delete this " + an[k].type + " annotation?")) { op("delete annot", () => E.deleteAnnot(S.doc, i, an[k].idx)); refreshPage(i); } return; } }
  };
}
$("#tools").onclick = (ev) => { const b = ev.target.closest("button"); if (!b) return; S.tool = b.dataset.t; document.querySelectorAll("#tools button").forEach(x => x.classList.toggle("on", x === b)); if (S.doc) document.querySelectorAll(".pg").forEach(p => drawWidgets(p, +p.dataset.i)); };

// ---------- toolbar actions ----------
const need = () => { if (!S.doc) { alert("Open a PDF first"); return false; } return true; };
const outName = (s) => S.name.replace(/\.pdf$/i, "") + s + ".pdf";
$("#bOpen").onclick = async () => { const [f] = await pickFiles(false); if (f) openBytes(f.bytes, f.name, f.handle); };
document.body.ondragover = (e) => e.preventDefault();
document.body.ondrop = async (e) => { e.preventDefault(); const f = e.dataTransfer.files[0]; if (f) openBytes(new Uint8Array(await f.arrayBuffer()), f.name); };
$("#bSave").onclick = async () => { if (!need()) return; const h = await writeOut(S.name, E.save(S.doc, "garbage=compact,compress=yes,incremental=no"), S.handle); if (h) S.handle = h; S.dirty = false; status("Saved " + S.name); };
$("#bSaveAs").onclick = async () => { if (!need()) return; const h = await writeOut(outName("-edited"), E.save(S.doc), null); if (h) { S.handle = h; S.name = h.name; } status("Saved copy"); };
$("#bUndo").onclick = async () => { S.doc.undo(); await buildAll(); updBtns(); };
$("#bRedo").onclick = async () => { S.doc.redo(); await buildAll(); updBtns(); };
$("#bZoomIn").onclick = () => { S.zoom = Math.min(3, S.zoom * 1.2); S.doc && buildAll(); };
$("#bZoomOut").onclick = () => { S.zoom = Math.max(0.4, S.zoom / 1.2); S.doc && buildAll(); };
$("#bFind").onclick = async () => {
  if (!need()) return; const r = await askDialog("Find text", [{ name: "q", label: "Text" }]); if (!r || !r.q) return;
  const n = S.doc.countPages(); let total = 0, first = -1;
  document.querySelectorAll(".find").forEach(e => e.remove());
  for (let i = 0; i < n; i++) { const hits = E.search(S.doc, i, r.q); if (!hits.length) continue; total += hits.length; if (first < 0) first = i;
    const pg = $("#pg" + i), sz = S.sizes[i];
    for (const q of hits) { const xs = [q[0], q[2], q[4], q[6]], ys = [q[1], q[3], q[5], q[7]]; const d = document.createElement("div"); d.className = "sel find"; d.style.cssText = `border:0;background:rgba(255,200,0,.4);left:${(Math.min(...xs) - sz.x) * S.zoom}px;top:${(Math.min(...ys) - sz.y) * S.zoom}px;width:${(Math.max(...xs) - Math.min(...xs)) * S.zoom}px;height:${(Math.max(...ys) - Math.min(...ys)) * S.zoom}px`; pg.appendChild(d); } }
  status(`${total} match(es)`); if (first >= 0) $("#pg" + first).scrollIntoView();
};
$("#bRedText").onclick = async () => {
  if (!need()) return; const r = await askDialog("Redact text", [{ name: "q", label: "Text to find and mark for redaction (all pages)" }, { type: "note", label: "Marks every match. Press 'Apply redactions' to permanently remove the text underneath." }], "Mark"); if (!r || !r.q) return;
  const n = op("redact text", () => E.redactText(S.doc, r.q)); S.doc.countPages(); for (let i = 0; i < S.doc.countPages(); i++) refreshPage(i); status(`${n} match(es) marked`);
};
$("#bApply").onclick = async () => {
  if (!need()) return; if (!confirm("Permanently remove all content under marked redaction boxes? You can still Undo until you save.")) return;
  op("apply redactions", () => E.applyRedactions(S.doc)); for (let i = 0; i < S.doc.countPages(); i++) refreshPage(i); status("Redactions applied");
};
$("#bMerge").onclick = async () => {
  const fs = await pickFiles(true); if (!fs.length) return;
  if (!S.doc) { const d = E.merge(fs.map(f => f.bytes)); await openBytes(E.save(d), "merged.pdf"); S.dirty = true; return; }
  op("merge", () => { for (const f of fs) { const src = E.open(f.bytes); for (let i = 0; i < src.countPages(); i++) S.doc.graftPage(-1, src, i); } }); await buildAll(); status(`Appended ${fs.length} file(s)`);
};
$("#bSplit").onclick = async () => {
  if (!need()) return; const n = S.doc.countPages();
  const r = await askDialog("Split", [{ name: "mode", label: "Mode", type: "select", options: [["ranges", "Page ranges (one file per range)"], ["every", "Every N pages"]] }, { name: "v", label: `Ranges like 1-3,5,8-  (of ${n}) or N`, value: "1" }], "Split"); if (!r) return;
  try {
    const bytes = E.save(S.doc); const parts = r.mode === "every" ? E.splitEvery(bytes, Math.max(1, +r.v)) : E.splitBy(bytes, r.v);
    let dir = null; if (window.showDirectoryPicker) { try { dir = await showDirectoryPicker({ mode: "readwrite" }); } catch { return; } }
    for (let k = 0; k < parts.length; k++) { const nm = outName("-part" + (k + 1)); if (dir) { const fh = await dir.getFileHandle(nm, { create: true }); const w = await fh.createWritable(); await w.write(parts[k]); await w.close(); } else await writeOut(nm, parts[k], null); }
    status(`Wrote ${parts.length} file(s)`);
  } catch (e) { alert(e.message); }
};
$("#bCompress").onclick = async () => {
  if (!need()) return; const r = await askDialog("Compress", [{ name: "l", label: "Level", type: "select", options: [["lossless", "Lossless (structure only)"], ["balanced", "Balanced (images ≤1800px, JPEG 65)"], ["strong", "Strong (images ≤1100px, JPEG 45)"]] }], "Compress"); if (!r) return;
  status("Compressing…"); await new Promise(r => setTimeout(r, 20));
  const before = E.save(S.doc).length; const out = E.compress(E.save(S.doc), r.l);
  const h = await writeOut(outName("-compressed"), out, null); status(`Compressed ${(before / 1024).toFixed(0)} KB → ${(out.length / 1024).toFixed(0)} KB${h ? "" : ""}`);
};
$("#bProt").onclick = async () => {
  if (!need()) return;
  const r = await askDialog("Password protection", [{ name: "u", label: "Open password (leave empty for none)", type: "password" }, { name: "o", label: "Owner password (to change permissions)", type: "password" },
    { name: "p", label: "Allow", type: "select", options: [["print,print-hq,copy,annotate,form,assemble,edit,accessibility", "Everything"], ["print,print-hq,annotate,form,accessibility", "Print + annotate + forms only (no copy/edit)"], ["accessibility", "Nothing (view only)"]] },
    { name: "rm", label: "Or remove existing password", type: "select", options: [["no", "No, set the passwords above"], ["yes", "Yes, save an unprotected copy"]] }], "Save protected copy"); if (!r) return;
  try { const out = r.rm === "yes" ? E.save(S.doc, "garbage=compact,compress=yes,encrypt=none") : E.protect(S.doc, { user: r.u, owner: r.o, perms: r.p }); await writeOut(outName(r.rm === "yes" ? "-unlocked" : "-protected"), out, null); status("Saved"); } catch (e) { alert(e.message); }
};
$("#bSign").onclick = async () => {
  if (!need()) return;
  const r = await askDialog("Sign with certificate", [{ name: "c", label: "Certificate (.pfx / .p12), optional", type: "file", accept: ".pfx,.p12" }, { name: "pw", label: "Certificate password", type: "password" }, { name: "reason", label: "Reason (optional)" }, { name: "loc", label: "Location (optional)" }, { name: "who", label: "Name (optional)" },
    { type: "note", label: "No certificate file? Leave it empty to sign with a new self-signed certificate (valid signature, but readers will show it as untrusted)." }], "Sign"); if (!r) return;
  const fd = new FormData(); fd.append("pdf", new Blob([E.save(S.doc)])); if (r.c) fd.append("pfx", r.c); else fd.append("gen", "1"); fd.append("password", r.pw); fd.append("reason", r.reason); fd.append("location", r.loc); fd.append("name", r.who);
  status("Signing…"); const res = await fetch("/api/sign", { method: "POST", body: fd });
  if (!res.ok) { alert("Signing failed: " + (await res.text())); status("Signing failed"); return; }
  await writeOut(outName("-signed"), new Uint8Array(await res.arrayBuffer()), null); status("Signed copy saved. Do not edit it afterwards (that breaks the signature).");
};

// ---------- OCR ----------
let ocrWorker = null;
async function getOcr() {
  if (ocrWorker) return ocrWorker;
  await new Promise((ok, no) => { if (window.Tesseract) return ok(); const s = document.createElement("script"); s.src = "vendor/ocr/tesseract.min.js"; s.onload = ok; s.onerror = no; document.head.appendChild(s); });
  const base = new URL("vendor/ocr/", location.href).href;
  ocrWorker = await Tesseract.createWorker("eng", 1, { workerPath: base + "worker.min.js", corePath: base + "tesseract-core-simd-lstm.wasm.js", langPath: base.slice(0, -1), gzip: false, workerBlobURL: false, cacheMethod: "none" });
  return ocrWorker;
}
$("#bOcr").onclick = async () => {
  if (!need()) return; const n = S.doc.countPages();
  const r = await askDialog("OCR (English)", [{ name: "s", label: "Pages", type: "select", options: [["cur", "Current page"], ["all", "All pages"]] }, { type: "note", label: "Each OCR'd page is replaced by its image plus an invisible searchable text layer. Undo is available before saving." }], "Run OCR"); if (!r) return;
  const pages = r.s === "all" ? [...Array(n).keys()] : [S.cur];
  try {
    status("Loading OCR engine…"); const w = await getOcr();
    for (const i of pages) {
      status(`OCR page ${i + 1} (${pages.indexOf(i) + 1}/${pages.length})…`);
      const png = E.renderPNG(S.doc, i, 3); const sz = E.pageSize(S.doc, i);
      const { data } = await w.recognize(new Blob([png], { type: "image/png" }), {}, { pdf: true });
      const src = E.open(new Uint8Array(data.pdf));
      op("ocr", () => { S.doc.graftPage(i + 1, src, 0); S.doc.deletePage(i); });
      // keep original page size
      refreshPage(i);
    }
    status(`OCR done on ${pages.length} page(s)`);
  } catch (e) { alert("OCR failed: " + (e.message || e)); status("OCR failed"); }
};

// ---------- AI ----------
const chat = [];
const cfg = () => JSON.parse(localStorage.getItem("litepdf.ai") || "{}");
$("#bAI").onclick = () => $("#side").classList.toggle("show");
$("#aiSet").onclick = async () => {
  const c = cfg(); const r = await askDialog("AI settings (stored only in this app's local storage)", [{ name: "p", label: "Provider", type: "select", options: [["gemini", "Google Gemini"], ["openrouter", "OpenRouter"]] }, { name: "k", label: "API key", type: "password", value: c.k || "" }, { name: "m", label: "Model id", value: c.m || "" }], "Save"); if (!r) return;
  if (!r.m) r.m = r.p === "gemini" ? "gemini-2.5-flash" : "google/gemini-2.5-flash";
  localStorage.setItem("litepdf.ai", JSON.stringify(r)); status("AI settings saved");
};
function say(cls, t) { const d = document.createElement("div"); d.className = cls; d.textContent = t; $("#chat").appendChild(d); $("#chat").scrollTop = 1e9; return d; }
async function post(url, key, body) {
  const res = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json", "X-Api-Key": key }, body: JSON.stringify(body) });
  const txt = await res.text(); let j; try { j = JSON.parse(txt); } catch { throw new Error(txt.slice(0, 200) || res.statusText); }
  if (!res.ok) throw new Error(j.error?.message || (typeof j.error === "string" ? j.error : "") || res.statusText); return j;
}
export async function callAI(c, system, history, pageImgB64) {
  const turns = history.map(h => ({ role: h.role, text: h.text }));
  if (c.p === "gemini") {
    const contents = turns.map((t, k) => ({ role: t.role === "user" ? "user" : "model", parts: [{ text: t.text }].concat(k === 0 && pageImgB64 ? [{ inline_data: { mime_type: "image/png", data: pageImgB64 } }] : []) }));
    const j = await post(`/api/ai?p=gemini&model=${encodeURIComponent(c.m)}`, c.k, { system_instruction: { parts: [{ text: system }] }, contents });
    return (j.candidates?.[0]?.content?.parts || []).map(p => p.text || "").join("") || "(empty reply)";
  }
  const messages = [{ role: "system", content: system }].concat(turns.map((t, k) => ({ role: t.role === "user" ? "user" : "assistant", content: k === 0 && pageImgB64 ? [{ type: "text", text: t.text }, { type: "image_url", image_url: { url: "data:image/png;base64," + pageImgB64 } }] : t.text })));
  const j = await post("/api/ai?p=openrouter", c.k, { model: c.m, messages });
  return j.choices?.[0]?.message?.content || "(empty reply)";
}
const b64 = (u8) => { let s = ""; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(s); };
async function aiSend(q) {
  if (!need()) return; const c = cfg(); if (!c.k) { $("#aiSet").click(); return; }
  const first = chat.length === 0; say("u", q);
  let pre = ""; let img = null;
  if (first) { if ($("#aiScope").value === "page") { img = b64(E.renderPNG(S.doc, S.cur, 2)); pre = `[Page ${S.cur + 1} of the PDF is attached as an image]\n\n`; } else pre = "DOCUMENT TEXT:\n" + E.docText(S.doc) + "\n\n"; }
  chat.push({ role: "user", text: pre + q }); const w = say("a", "…");
  try { const a = await callAI(c, "You answer questions about the user's PDF accurately and concisely. If something is not in the document, say so.", chat, img); chat.push({ role: "model", text: a }); w.textContent = a; }
  catch (e) { chat.pop(); w.textContent = "Error: " + e.message; }
}
$("#aiSum").onclick = () => aiSend("Summarise this document in a short list of key points.");
$("#aiAsk").onclick = () => { const q = $("#aiq").value.trim(); if (q) { $("#aiq").value = ""; aiSend(q); } };
window.addEventListener("beforeunload", (e) => { if (S.dirty) { e.preventDefault(); e.returnValue = ""; } });
