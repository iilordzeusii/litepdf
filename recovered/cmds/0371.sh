cd ~/.cargo/registry/src/*/mupdf-0.8.0/src; grep -rn "struct AnnotationDefaultAppearance" -A8 pdf/annotation.rs; sed -n 1128,1185p pdf/annotation.rs
