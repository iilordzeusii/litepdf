cd /tmp/scratch/app/src; wc -l *.rs; grep -n -E '^\s*(pub )?(fn|struct|impl|enum)|^use ' app.rs | head -150
