// PDF engine: thin wrappers over MuPDF (WASM). Runs in the browser and in Node (for tests).
import * as mupdf from "./vendor/mupdf.js";
export { mupdf };

export function open(bytes, password) {
  const doc = mupdf.Document.openDocument(bytes, "application/pdf");
  if (doc.needsPassword()) {
    if (!password || !doc.authenticatePassword(password)) { const e = new Error("password required"); e.code = "PASSWORD"; throw e; }
  }
  return doc.asPDF() || doc;
}

export function save(doc, opts = "garbage=compact,compress=yes") {
  return doc.saveToBuffer(opts).asUint8Array().slice();
}

export function renderPNG(doc, i, scale = 1.5) {
  const page = doc.loadPage(i);
  const pix = page.toPixmap(mupdf.Matrix.scale(scale, scale), mupdf.ColorSpace.DeviceRGB, false, true);
  const png = pix.asPNG();
  pix.destroy();
  return png;
}
export function renderPixmap(doc, i, scale = 1.5) {
  const page = doc.loadPage(i);
  const pix = page.toPixmap(mupdf.Matrix.scale(scale, scale), mupdf.ColorSpace.DeviceRGB, false, true);
  const out = { w: pix.getWidth(), h: pix.getHeight(), rgba: null };
  const png = pix.asPNG(); pix.destroy(); out.png = png; return out;
}
export function pageSize(doc, i) { const b = doc.loadPage(i).getBounds(); return { w: b[2] - b[0], h: b[3] - b[1], x: b[0], y: b[1] }; }

export function pageText(doc, i) { return doc.loadPage(i).toStructuredText("preserve-whitespace").asText(); }
export function docText(doc, maxChars = 120000) {
  let s = ""; const n = doc.countPages();
  for (let i = 0; i < n && s.length < maxChars; i++) s += `\n--- page ${i + 1} ---\n` + pageText(doc, i);
  return s.slice(0, maxChars);
}
export function search(doc, i, needle) { return doc.loadPage(i).search(needle).flat(); }
// Quads for a selection rectangle (page coordinates)
export function selectionQuads(doc, i, p1, p2) {
  const st = doc.loadPage(i).toStructuredText("preserve-whitespace");
  return st.highlight(p1, p2);
}
export function selectionText(doc, i, p1, p2) {
  return doc.loadPage(i).toStructuredText("preserve-whitespace").copy(p1, p2);
}

// ---- annotations ----
const COLORS = { yellow: [1, 0.9, 0], green: [0.2, 0.8, 0.3], red: [0.9, 0.1, 0.1], blue: [0.1, 0.4, 0.95], black: [0, 0, 0] };
export function col(c) { return Array.isArray(c) ? c : (COLORS[c] || COLORS.yellow); }

export function addMarkup(doc, i, type, quads, color = "yellow") {
  const page = doc.loadPage(i);
  const a = page.createAnnotation(type);
  a.setColor(col(color));
  a.setQuadPoints(quads);
  a.update();
  return a;
}
export function addInk(doc, i, strokes, color = "red", width = 2) {
  const a = doc.loadPage(i).createAnnotation("Ink");
  a.setColor(col(color)); a.setBorderWidth(width); a.setInkList(strokes); a.update(); return a;
}
export function addNote(doc, i, pt, text) {
  const a = doc.loadPage(i).createAnnotation("Text");
  a.setRect([pt[0], pt[1], pt[0] + 20, pt[1] + 20]); a.setContents(text); a.update(); return a;
}
export function addFreeText(doc, i, rect, text, size = 12, color = "black") {
  const a = doc.loadPage(i).createAnnotation("FreeText");
  a.setRect(rect); a.setContents(text); a.setDefaultAppearance("Helv", size, col(color)); a.update(); return a;
}
export function addShape(doc, i, type, rect, color = "red", width = 2) {
  const a = doc.loadPage(i).createAnnotation(type); // Square | Circle
  a.setRect(rect); a.setColor(col(color)); a.setBorderWidth(width); a.update(); return a;
}
export function addLine(doc, i, p1, p2, color = "red", width = 2) {
  const a = doc.loadPage(i).createAnnotation("Line");
  a.setLine(p1, p2); a.setColor(col(color)); a.setBorderWidth(width); a.update(); return a;
}
export function listAnnots(doc, i) {
  return doc.loadPage(i).getAnnotations().map((a, idx) => ({ idx, type: a.getType(), rect: a.getBounds(), contents: a.getContents() }));
}
export function deleteAnnot(doc, i, idx) {
  const page = doc.loadPage(i); const a = page.getAnnotations()[idx]; page.deleteAnnotation(a);
}

// ---- forms ----
export function listWidgets(doc, i) {
  return doc.loadPage(i).getWidgets().map((w, idx) => ({ idx, type: w.getFieldType(), name: w.getName(), value: w.getValue(), rect: w.getBounds(), readOnly: w.isReadOnly(), options: (() => { try { return w.getOptions(); } catch { return []; } })() }));
}
export function setWidget(doc, i, idx, value) {
  const w = doc.loadPage(i).getWidgets()[idx];
  const t = w.getFieldType();
  if (t === "text") w.setTextValue(String(value));
  else if (t === "checkbox" || t === "radiobutton") { if ((w.getValue() === "Off" || !w.getValue()) === !!value) w.toggle(); }
  else if (t === "combobox" || t === "listbox") w.setChoiceValue(String(value));
  w.update();
}

// ---- page operations ----
export function merge(buffers) {
  const out = new mupdf.PDFDocument();
  for (const b of buffers) {
    const src = open(b);
    const n = src.countPages();
    for (let i = 0; i < n; i++) out.graftPage(-1, src, i);
  }
  return out;
}
// ranges like "1-3,5,8-" (1-based). Returns array of arrays of 0-based page indexes
export function parseRanges(spec, n) {
  const out = [];
  for (const part of String(spec).split(",").map(s => s.trim()).filter(Boolean)) {
    const m = part.match(/^(\d*)\s*-\s*(\d*)$/);
    let a, b;
    if (m) { a = m[1] ? +m[1] : 1; b = m[2] ? +m[2] : n; } else if (/^\d+$/.test(part)) { a = b = +part; } else throw new Error("Bad range: " + part);
    if (a < 1 || b > n || a > b) throw new Error(`Range out of bounds: ${part} (document has ${n} pages)`);
    const r = []; for (let p = a; p <= b; p++) r.push(p - 1); out.push(r);
  }
  return out;
}
export function extractPages(doc, pages) {
  const out = new mupdf.PDFDocument();
  for (const p of pages) out.graftPage(-1, doc, p);
  return out;
}
export function splitBy(buffer, spec) {
  const src = open(buffer); const n = src.countPages();
  return parseRanges(spec, n).map(pages => save(extractPages(src, pages)));
}
export function splitEvery(buffer, k) {
  const src = open(buffer); const n = src.countPages(); const res = [];
  for (let s = 0; s < n; s += k) res.push(save(extractPages(src, [...Array(Math.min(k, n - s)).keys()].map(x => s + x))));
  return res;
}
// order: array of 0-based indexes in new order (deleted pages simply omitted)
export function reorder(doc, order) { doc.rearrangePages(order); }
export function rotatePage(doc, i, deg) {
  const p = doc.loadPage(i); const cur = p.getObject().getInheritable("Rotate"); const r = ((cur && !cur.isNull() ? cur.asNumber() : 0) + deg + 360) % 360;
  p.getObject().put("Rotate", doc.newInteger(r));
}

// ---- security ----
export function protect(doc, { user = "", owner = "", perms = "print,copy,edit,annotate,form,assemble" } = {}) {
  if (!user && !owner) throw new Error("Give a user or owner password");
  const pw = (s) => s.replace(/,/g, "\u200b,"); // never allow option injection
  if (/[,=]/.test(user + owner)) throw new Error("Passwords cannot contain , or =");
  let o = "garbage=compact,compress=yes,encrypt=aes-256";
  o += `,owner-password=${owner || user}`;
  if (user) o += `,user-password=${user}`;
  o += `,permissions=${permString(perms)}`;
  return save(doc, o);
}
function permString(perms) {
  // MuPDF permissions option takes letters: print=p, edit=e, copy=c, annotate=a, form=f, accessibility... use numeric bitmask instead
  const m = { print: 4, edit: 8, copy: 16, annotate: 32, form: 256, accessibility: 512, assemble: 1024, "print-hq": 2048 };
  let v = 0xfffff0c0 | 0; // required-1 bits
  for (const k of String(perms).split(",").map(s => s.trim())) v |= m[k] || 0;
  return String(v | 0);
}
export function unprotect(buffer, password) { const d = open(buffer, password); return save(d, "garbage=compact,compress=yes,encrypt=none"); }

// ---- redaction ----
export function redactRects(doc, i, rects) {
  const page = doc.loadPage(i);
  for (const r of rects) { const a = page.createAnnotation("Redact"); a.setRect(r); a.update(); }
}
export function redactText(doc, needle) {
  let hits = 0; const n = doc.countPages();
  for (let i = 0; i < n; i++) {
    const page = doc.loadPage(i); const quads = page.search(needle).flat();
    for (const q of quads) { const a = page.createAnnotation("Redact"); a.setQuadPoints([q]); a.update(); hits++; }
  }
  return hits;
}
export function applyRedactions(doc) {
  const n = doc.countPages();
  for (let i = 0; i < n; i++) {
    const page = doc.loadPage(i);
    if (page.getAnnotations().some(a => a.getType() === "Redact"))
      page.applyRedactions(true, mupdf.PDFPage.REDACT_IMAGE_PIXELS, mupdf.PDFPage.REDACT_LINE_ART_REMOVE_IF_TOUCHED, mupdf.PDFPage.REDACT_TEXT_REMOVE);
  }
}

// ---- compression ----
export function compress(buffer, level = "balanced") {
  const doc = open(buffer);
  if (level !== "lossless") downsampleImages(doc, level === "strong" ? { maxDim: 1100, q: 45 } : { maxDim: 1800, q: 65 });
  try { doc.subsetFonts(); } catch { }
  return save(doc, "garbage=deduplicate,compress=yes,compress-fonts=yes,compress-images=yes,clean=yes");
}
function downsampleImages(doc, { maxDim, q }) {
  const n = doc.countObjects();
  for (let x = 1; x < n; x++) {
    try {
      const o = doc.newIndirect(x);
      if (!o.isStream()) continue;
      const st = o.get("Subtype"); if (!st || !st.isName() || st.asName() !== "Image") continue;
      const sm = o.get("SMask"); if (sm && !sm.isNull()) continue; // keep transparency intact
      const im = o.get("ImageMask"); if (im && !im.isNull() && im.asBoolean()) continue;
      const w = o.get("Width").asNumber(), h = o.get("Height").asNumber();
      const img = doc.loadImage(o);
      const f = Math.max(w, h) > maxDim ? maxDim / Math.max(w, h) : 1;
      const w2 = Math.max(1, Math.round(w * f)), h2 = Math.max(1, Math.round(h * f));
      const gray = img.getNumberOfComponents() === 1;
      const cs = gray ? mupdf.ColorSpace.DeviceGray : mupdf.ColorSpace.DeviceRGB;
      const pix = new mupdf.Pixmap(cs, [0, 0, w2, h2], false); pix.clear(255);
      const dev = new mupdf.DrawDevice(mupdf.Matrix.identity, pix);
      dev.fillImage(img, [w2, 0, 0, h2, 0, 0], 1); dev.close();
      const jpg = pix.asJPEG(q);
      if (jpg.length >= o.readRawStream().length) continue; // only replace when smaller
      o.writeRawStream(jpg);
      o.put("Filter", doc.newName("DCTDecode")); o.delete("DecodeParms");
      o.put("Width", doc.newInteger(w2)); o.put("Height", doc.newInteger(h2));
      o.put("ColorSpace", doc.newName(gray ? "DeviceGray" : "DeviceRGB")); o.put("BitsPerComponent", doc.newInteger(8));
    } catch (e) { if (globalThis.__dbg) console.log("img skip", x, e.message); }
  }
}
