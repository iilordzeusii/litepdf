cd /tmp/scratch/app/src; sed -n "$(grep -n 'pub fn render_job_doc' render.rs | cut -d: -f1),+40p" render.rs | cut -c1-220
