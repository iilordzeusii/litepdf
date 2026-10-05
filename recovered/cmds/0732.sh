cd /tmp; sed -n 155,200p gd.ts; grep -n 'private onPinchUpdate_\|onPinchEnd_\|private onPinchStart_' vp.ts | head; sed -n "$(grep -n 'private onPinchUpdate_' vp.ts | cut -d: -f1),+50p" vp.ts
