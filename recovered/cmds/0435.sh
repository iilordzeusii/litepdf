cd /tmp/scratch/app/src; sed -i 's/^mod extras;/mod extras;\nmod ocr;/' main.rs; grep -n "pub path\|self.path\|fn open\|fn ui\|top_panel\|TopBottomPanel\|Panel::\|cur_page\b" app.rs | head -50
