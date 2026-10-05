cd /tmp/scratch/app/src; grep -n 'pub fn quad_rect' -A4 ops.rs; sed -n '/pub fn page_chars/,/^    }/p' app.rs | head -30; grep -n 'cmds\|tx.send\|\.tx\.' app.rs | cut -c1-150
