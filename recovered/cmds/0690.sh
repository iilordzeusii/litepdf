tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --message-stdin <<'EOF'
Plan only, nothing built. Based on b7 code (read just now).

(a) AI today
- One feature: a right-side AI chat panel (AI button in the menu bar), Gemini or OpenRouter, key stored locally only. No other AI paths (no RAG, no auto-summaries).
- What it sends on each question: your whole chat history plus, by checkbox, (1) "Send current page text" (default ON): text of the page you are on, (2) "Send text of whole document": every page's text, no cap at all, so a 339-page book sends all 339 pages every message, (3) "Send current page image": one JPEG of the current page at 1.6x. Nothing is sent in the background.
- Proposed smallest UI, in the AI settings block, replacing the three checkboxes with one "Pages sent to AI" selector: Current page (default) / Page range [from] [to] (e.g. 1-20) / Whole document, plus a "Max pages" cap field (default 30) that always applies, and a live line under it: "Sending text of pages 1-20 (20 pages, ~N characters)". Image checkbox stays and follows the same rule: current page only, or each page in the range up to a small cap (5). If the range exceeds the cap it is trimmed to the cap and the line says so before sending. One code path (ask_ai) feeds everything, so the limit covers every AI call. Optional: a "Selected text only" choice using his current selection.
- Not verifiable here: real API calls (no key on this box), so I would only verify the page-selection logic and the preview line headlessly; the actual request on his PC.

(b) Tabs
- Present in b7 (and b4+): tab strip across the top (file name, * when unsaved, x to close, middle-click closes, + opens a file in a new tab), Ctrl+Tab / Ctrl+Shift+Tab to switch, Ctrl+W to close (asks if unsaved), drag-and-drop of PDFs opens new tabs, re-opening an already open file switches to its tab, each tab keeps its own page position, zoom, selection, find and undo state, OCR is tied to its tab. Verified headless only in Wine (open, switch 0.3 ms, close, re-open dedupe). He has not confirmed it on his PC, so first ask whether he sees the strip under the menu bar; if not, that is a bug to chase.
- Missing and what I would add: Ctrl+T (new empty tab), Ctrl+O opening in a new tab, Ctrl+1..9 jump, Ctrl+Shift+T reopen closed tab, drag-to-reorder tabs, right-click menu (close others / copy path), scroll the strip with the wheel when many tabs, and File > Open using a new tab when the current tab already has a document. Smallest useful set: Ctrl+T, Ctrl+1..9, reorder, right-click close others. Say which he wants.

Waiting for his go. Viewer, rendering and input handling stay exactly as in b7. Repo not pushed.
EOF
