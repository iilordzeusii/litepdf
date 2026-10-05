cd /tmp/scratch/app/src; sed -n 60,76p extras.rs | cut -c1-400; grep -n 'ai_scope_doc' app.rs | cut -c1-80; grep -n 'ai_chat' *.rs bin/*.rs | cut -c1-120
