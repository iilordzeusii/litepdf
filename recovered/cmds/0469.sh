cd /tmp/scratch/app/src; python3 - <<'E'
s=open('ops.rs').read()
a=s.index("/// Downsample large images"); b=s.index("    save(&d, out, true)?;\n    Ok((replaced, seen))")
new='''/// Downsample large images and re-encode them as JPEG (raw, Flate, JPEG and ICC based RGB/gray images), then garbage-collect.
/// An image is replaced only when the new data is clearly smaller than the stream it replaces.
pub fn compress(input: &str, out: &str, max_dim: u32, quality: u8) -> Result<(usize, usize), Error> {
    let mut d = PdfDocument::open(input)?;
    let mut done = std::collections::HashSet::new();
    let (mut replaced, mut seen) = (0, 0);
    for pi in 0..d.page_count()? {
        let mut page = d.load_pdf_page(pi)?;
        for info in page.images()? {
            if !done.insert(info.xref) { continue; }
            seen += 1;
            if info.bits_per_component.map(|b| b != 8).unwrap_or(false) { continue; }
            let cs = info.color_space.clone().unwrap_or_default();
            if cs.contains("Indexed") || cs.contains("Separation") || cs.contains("DeviceN") || cs.contains("CMYK") || cs.contains("Lab") { continue; }
            if !(cs.contains("DeviceRGB") || cs.contains("DeviceGray") || cs.contains("ICC") || cs.contains("CalRGB") || cs.contains("CalGray")) { continue; }
            let Ok(o) = d.new_indirect(info.xref, 0) else { continue };
            if o.get_dict("SMask").ok().flatten().is_some() || o.get_dict("Mask").ok().flatten().is_some() || o.get_dict("Decode").ok().flatten().is_some() { continue; }
            let orig_len = o.get_dict("Length").ok().flatten().and_then(|l| l.resolve().ok().flatten().unwrap_or(l).as_int().ok()).unwrap_or(i32::MAX) as usize;
            let Ok(raw) = o.read_stream() else { continue };
            let (w0, h0) = (info.width as usize, info.height as usize);
            if w0 == 0 || h0 == 0 || raw.len() % (w0 * h0) != 0 { continue; }
            let comps = raw.len() / (w0 * h0);
            if comps != 1 && comps != 3 { continue; }
            let f = ((w0.max(h0) as f32) / max_dim as f32).ceil().max(1.0) as usize;
            let (w, h) = (w0 / f, h0 / f);
            if w == 0 || h == 0 { continue; }
            let mut px = vec![0u8; w * h * comps];
            if f == 1 { px.copy_from_slice(&raw[..w * h * comps]); } else {
                for y in 0..h { for x in 0..w { for c in 0..comps {
                    let mut sum = 0u32;
                    for dy in 0..f { for dx in 0..f { sum += raw[((y * f + dy) * w0 + (x * f + dx)) * comps + c] as u32; } }
                    px[(y * w + x) * comps + c] = (sum / (f * f) as u32) as u8;
                } } }
            }
            let ct = if comps == 3 { jpeg_encoder::ColorType::Rgb } else { jpeg_encoder::ColorType::Luma };
            let mut buf = vec![];
            if jpeg_encoder::Encoder::new(&mut buf, quality).encode(&px, w as u16, h as u16, ct).is_err() { continue; }
            if buf.len() as f32 > orig_len as f32 * 0.9 { continue; }
            if page.replace_image(&mut d, info.xref, PageImageSource::Bytes { data: &buf, format_hint: Some("jpeg") }).is_ok() { replaced += 1; }
        }
    }
'''
s=s[:a]+new+s[b:]
open('ops.rs','w').write(s)
t=open('app.rs').read()
t=t.replace("pub ocr_force: bool,","pub ocr_force: bool, pub comp_dpi: f32,",1).replace("ocr_force: false,","ocr_force: false, comp_dpi: 150.0,",1)
t=t.replace('''ui.label("JPEG quality for images (lower = smaller):"); ui.add(egui::Slider::new(&mut self.quality, 20.0..=95.0));''','''ui.label("JPEG quality for images (lower = smaller):"); ui.add(egui::Slider::new(&mut self.quality, 20.0..=95.0));
                    ui.label("Image resolution (scans are shrunk to about this many dots per inch on an A4 page):");
                    ui.horizontal(|ui| { for d in [100.0f32, 150.0, 200.0, 300.0] { ui.selectable_value(&mut self.comp_dpi, d, format!("{d:.0} dpi")); } });
                    ui.label("Images that would not get smaller are left untouched. If the result is not smaller the original is kept.");''',1)
t=t.replace("ops::compress(&snap, &tmpo, 1600, self.quality as u8)","ops::compress(&snap, &tmpo, (self.comp_dpi * 11.7) as u32, self.quality as u8)",1)
t=t.replace('''                                match self.commit_file(&tmpo, &out) {''','''                                if s1 >= s0 { let _ = std::fs::remove_file(&tmpo); self.status = format!("No size gain ({a} of {b} images changed, {} KB before, {} KB after). Nothing saved.", s0 / 1024, s1 / 1024); } else
                                match self.commit_file(&tmpo, &out) {''',1)
open('app.rs','w').write(t)
E
cd ..; source /tmp/scratch/wenv.sh >/dev/null 2>&1; cargo build --release --target x86_64-pc-windows-gnu --bin litepdf 2>&1 | grep -E "^error|Finished" -A8 | head -40
