cd /tmp/scratch/app/src; sed -n 690,712p app.rs | cut -c1-200; grep -n 'fn ocr_child_main\|pub fn settings_path' extras.rs
