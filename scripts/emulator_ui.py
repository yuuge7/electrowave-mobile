"""Small emulator-only UI helper for manual QA; uses Android accessibility nodes."""
import argparse, os, re, subprocess, xml.etree.ElementTree as ET
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('action',choices=['dump','tap','screenshot']);parser.add_argument('value',nargs='?');parser.add_argument('--device',default='emulator-5554');args=parser.parse_args()
adb=str(Path(os.environ['LOCALAPPDATA'])/'Android/Sdk/platform-tools/adb.exe')
def command(*parts):
    return subprocess.check_output([adb,'-s',args.device,*parts])
if command('shell','getprop','ro.kernel.qemu').strip()!=b'1':raise SystemExit('This helper only targets an Android emulator.')
command('shell','input','keyevent','224')
command('shell','wm','dismiss-keyguard')
if args.action=='screenshot':
    if not args.value:raise SystemExit('Choose an output PNG path')
    output=Path(args.value)
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_bytes(command('exec-out','screencap','-p'));raise SystemExit()
dump=subprocess.check_output([adb,'-s',args.device,'shell','uiautomator','dump','/sdcard/electrowave-ui.xml'],stderr=subprocess.STDOUT)
if b'ERROR' in dump:raise SystemExit('Android accessibility is not ready; retry after the screen wakes.')
raw=command('shell','cat','/sdcard/electrowave-ui.xml')
root=ET.fromstring(raw[raw.find(b'<?xml'):])
nodes=[n for n in root.iter('node') if n.get('text') or n.get('content-desc')]
if args.action=='dump':
    for n in nodes:print(repr(n.get('text') or n.get('content-desc')),n.get('bounds'),n.get('resource-id'))
else:
    exact=[n for n in nodes if args.value.casefold() in [n.get('text','').casefold(),n.get('content-desc','').casefold()]]
    matches=exact or [n for n in nodes if args.value.casefold() in (n.get('text','')+' '+n.get('content-desc','')).casefold()]
    clickable=[n for n in matches if n.get('clickable')=='true']
    if len(clickable)==1:matches=clickable
    if len(matches)!=1:
        for n in matches:print(repr(n.get('text') or n.get('content-desc')),n.get('bounds'))
        raise SystemExit(f'Expected one matching node; found {len(matches)}')
    coordinates=list(map(int,re.findall(r'\d+',matches[0].get('bounds',''))))
    x1,y1,x2,y2=coordinates;command('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
