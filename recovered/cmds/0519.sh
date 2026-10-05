cd /tmp/scratch/app; python3 -c "import reportlab;print('rl')" 2>&1; python3 -c "import fitz;print('fitz')" 2>&1|tail -1; which mutool qpdf
