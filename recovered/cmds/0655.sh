cd /tmp/scratch/app/src; sed -i 's/    let (scale, rect) = match kind {/    let (scale, rect) = match kind {\n        Kind::Text => return None,/' render.rs; sed -n 170,182p render.rs | cut -c1-120
