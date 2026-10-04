#!/bin/sh
# builds go/dist (gzipped web assets) then the Windows exe
set -e
cd "$(dirname "$0")"
[ -f web/vendor/mupdf-wasm.wasm ] || sh scripts/vendor.sh
rm -rf go/dist && mkdir -p go/dist
(cd web && find . -type f ! -name package.json | while read f; do mkdir -p "../go/dist/$(dirname "$f")"; gzip -9 -n -c "$f" > "../go/dist/$f.gz"; done)
cd go
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -H=windowsgui" -o ../litepdf.exe .
CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o ../litepdf-linux-test .
ls -l ../litepdf.exe
