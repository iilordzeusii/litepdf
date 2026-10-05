tools agent_message send --to agent-01M2K1RFG71SJETW3996TFKAT0 --attachments /downloads/LitePDF-Setup.exe.part1,/downloads/LitePDF-Setup.exe.part2 --message-stdin <<'EOF'
Milestone installer in two byte-exact parts (zoom lag fix and tabs are NOT done, so this is the existing milestone build). Join in order: cat LitePDF-Setup.exe.part1 LitePDF-Setup.exe.part2 > LitePDF-Setup.exe
- part1: 16,000,000 bytes; part2: 15,088,784 bytes
- Full file: LitePDF-Setup.exe, 31,088,784 bytes, SHA-256 e6fdc0640462806727c8d23203ea887ba41dd4d15056badd8b84f2a45705f96d (I verified that part1+part2 joined gives exactly this hash).
Contents and what is verified vs untested are in my checkpoint message of 7:31 PM (PaddleOCR with DirectML+CPU fallback, skip-text + force, page box, filename in title/toolbar, compress rework, icon). Not in this build: zoom lag fix, tabs. Please re-check the SHA-256 after rejoining.
EOF
