cd /tmp/scratch/app/src; sed -n '/^    fn dialogs/,/^    fn sign_pad/p' app.rs | grep -n 'Dlg::None\|close {' | head; grep -n 'if close' app.rs | head
