cargo(){ :; }; rustc(){ :; }; rustup(){ :; }; tools(){ :; }; wine(){ :; }; wine64(){ :; }; makensis(){ :; }
sleep(){ :; }; pkill(){ :; }; pgrep(){ :; }; pip(){ :; }; apt-get(){ :; }; Xvfb(){ :; }; xvfb-run(){ :; }; nohup(){ :; }
timeout(){ shift; "$@"; }
export -f cargo rustc rustup tools wine wine64 makensis sleep pkill pgrep pip apt-get Xvfb xvfb-run nohup timeout
