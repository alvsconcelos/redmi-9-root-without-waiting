#!/usr/bin/env bash
# Lista os dispositivos USB e avisa quando aparecer um MediaTek em BROM/Preloader de verdade.
# ATENCAO: Xiaomi em "factory mode" tambem usa VID 0e8d (pid 200e) e NAO serve.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

PY=".venv/bin/python"

dump() {
  ioreg -a -p IOUSB -l -w 0 2>/dev/null | "$PY" -c '
import plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
GOOD = {0x0003: "BROM", 0x2000: "PRELOADER", 0x2001: "DA"}

def walk(n):
    if isinstance(n, dict):
        if "idVendor" in n:
            vid = n.get("idVendor", 0); pid = n.get("idProduct", 0)
            name = n.get("USB Product Name", "?")
            vend = n.get("USB Vendor Name", "?")
            if vid == 0x0E8D and pid in GOOD:
                mark = "   <== MEDIATEK %s (OK para unlock)" % GOOD[pid]
            elif vid == 0x0E8D and pid == 0x200E:
                mark = "   <== FACTORY MODE (NAO e BROM)"
            else:
                mark = ""
            print("  %-8s %-22s vid=0x%04x pid=0x%04x%s" % (vend, name, vid, pid, mark))
        for v in n.values():
            walk(v)
    elif isinstance(n, list):
        for x in n:
            walk(x)

walk(d.get("IORegistryEntryChildren", []))
'
}

found_ok() { dump | grep -q "MEDIATEK BROM\|MEDIATEK PRELOADER\|MEDIATEK DA"; }

echo "Dispositivos USB agora:"
dump
echo

if found_ok; then
  echo "BROM/Preloader ja conectado: rode ./unlock.sh"
  exit 0
fi

echo "Aguardando BROM/Preloader (0e8d:0003 ou 0e8d:2000)... Ctrl+C para sair."
echo "Dica: desligado, segure Vol+ + Power (ou Vol- + Power) e conecte o cabo."
while true; do
  if found_ok; then
    echo
    echo "==> MediaTek em modo correto:"
    dump
    echo "Rode ./unlock.sh AGORA e nao desconecte o cabo."
    exit 0
  fi
  sleep 2
done
