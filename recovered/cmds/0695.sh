ls /tmp/aitest.rs; which rustc; source /tmp/scratch/wenv.sh; which rustc; cd /tmp; timeout 60 rustc -o /tmp/aitest /tmp/aitest.rs 2>&1 | head -5; /tmp/aitest
