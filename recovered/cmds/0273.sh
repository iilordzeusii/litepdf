cd /tmp/scratch/app/src && python3 - <<'EOF'
s=open('ops.rs').read()
a=s.index("            let Ok(ex) = d.extract_image")
b=s.index("            if page.replace_image")
new='''            let comps = match info.color_space.as_deref() { Some("/DeviceRGB") => 3usize, Some("/DeviceGray") => 1, _ => continue };
            if info.bits_per_component != Some(8) { continue; }
            let Ok(o) = d.new_indirect(info.xref, 0) else { continue };
            let Ok(raw) = o.read_stream() else { continue };
            let (w0, h0) = (info.width as usize, info.height as usize);
            if raw.len() != w0 * h0 * comps { continue; }
            let f = ((w0.max(h0) as f32) / max_dim as f32).ceil().max(1.0) as usize;
            let (w, h) = (w0 / f, h0 / f);
            if w == 0 || h == 0 { continue; }
            let mut px = vec![0u8; w * h * comps];
            for y in 0..h { for x in 0..w { for c in 0..comps {
                let mut sum = 0u32;
                for dy in 0..f { for dx in 0..f { sum += raw[((y * f + dy) * w0 + (x * f + dx)) * comps + c] as u32; } }
                px[(y * w + x) * comps + c] = (sum / (f * f) as u32) as u8;
            } } }
            let ct = if comps == 3 { jpeg_encoder::ColorType::Rgb } else { jpeg_encoder::ColorType::Luma };
            let mut buf = vec![];
            if jpeg_encoder::Encoder::new(&mut buf, quality).encode(&px, w as u16, h as u16, ct).is_err() { continue; }
'''
s=s[:a]+new+s[b:]
s=s.replace("use mupdf::Image;\n","")
open('ops.rs','w').write(s)
EOF
cd /tmp/scratch/shot; source ~/.cargo/env; (RUST_FONTCONFIG_DLOPEN=1 BINDGEN_EXTRA_CLANG_ARGS="-I/usr/lib/gcc/x86_64-linux-gnu/11/include" LIBCLANG_PATH=/usr/local/lib/python3.10/dist-packages/clang/native timeout 100 cargo build --release --bin optest 2>&1 | grep -E "^error" -A9 | head -30 | cut -c1-160); ./target/release/optest ../t.pdf 2>&1 | tail -1; ls -la ../t.pdf ../o_cmp.pdf | awk '{print $5,$9}'; pdfimages -list ../o_cmp.pdf | tail -1; pdftoppm -r 60 -png ../o_cmp.pdf ../cmp >/dev/null 2>&1; ls ../cmp*
