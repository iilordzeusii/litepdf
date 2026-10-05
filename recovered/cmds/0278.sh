D=$(ls -d ~/.cargo/registry/src/*/underskrift-0.1.4); grep -rn "pub fn sign_blocking\|pub async fn sign\|pub fn sign" $D/src | head; cat $D/examples/sign_simple.rs | head -50; openssl version
