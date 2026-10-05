cd /tmp/scratch/app/src; grep -n "load_page" app.rs | head -3; grep -n "fn page_chars" -A6 app.rs | head -12; sed -n 372,374p app.rs | cut -c1-300
