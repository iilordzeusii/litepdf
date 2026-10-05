cd /tmp/scratch/app/src; sed -n 385,400p app.rs | cut -c1-200; echo ----; grep -n 'perf.mark("requests")' app.rs; sed -n 500,520p app.rs | cut -c1-220; grep -n 'struct Perf' app.rs
