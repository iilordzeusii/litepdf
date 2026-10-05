cd /tmp/scratch/app/src; python3 - <<'E'
s=open('ocr.rs').read()
s=s.replace("boxes.sort_by(|a, b| { let ha = a[3] - a[1]; if (a[1] - b[1]).abs() < ha * 0.5 { a[0].total_cmp(&b[0]) } else { a[1].total_cmp(&b[1]) } });",
"boxes.sort_by(|a, b| a[1].total_cmp(&b[1]));\n        { let mut i = 0; while i < boxes.len() { let (y0, hh) = (boxes[i][1], boxes[i][3] - boxes[i][1]); let mut j = i + 1; while j < boxes.len() && (boxes[j][1] - y0).abs() < hh * 0.5 { j += 1; } boxes[i..j].sort_by(|a, b| a[0].total_cmp(&b[0])); i = j; } }")
s=s.replace("words.sort_by(|a, b| { if (a.y - b.y).abs() < a.h * 0.5 { a.x.total_cmp(&b.x) } else { a.y.total_cmp(&b.y) } });",
"words.sort_by(|a, b| a.y.total_cmp(&b.y));\n        { let mut i = 0; while i < words.len() { let (y0, hh) = (words[i].y, words[i].h); let mut j = i + 1; while j < words.len() && (words[j].y - y0).abs() < hh * 0.5 { j += 1; } words[i..j].sort_by(|a, b| a.x.total_cmp(&b.x)); i = j; } }")
open('ocr.rs','w').write(s)
E
cd ..; source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu 2>&1 | grep -E "^error" -A9; cd /tmp/scratch/wt; source /tmp/scratch/wenv2.sh >/dev/null 2>&1
cp /tmp/scratch/app/target/x86_64-pc-windows-gnu/release/{ocrcli,litepdf}.exe .
D="/tmp/scratch/wp/drive_c/users/sandbox/Application Data/LitePDF"; rm -f "$D"/*.log
( time timeout 110 $WINE ocrcli.exe book.pdf book_o.pdf ) 2>&1 | grep -E "OCR|words|real"; ls "$D"; grep -E "page|WORKER|memory|failed" "$D/ocr.log"
