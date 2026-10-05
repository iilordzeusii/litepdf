cd /tmp/scratch/app/src; sed -n 1,60p bin/uitest.rs | cut -c1-260; grep -n 'pub fn tile_grid\|fn tile_grid\|fn tile_missing' app.rs
