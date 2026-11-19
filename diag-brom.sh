#!/usr/bin/env bash
# Diagnostico: espera BROM (0e8d:0003) ou preloader (0e8d:2000) e testa
# quais transfers USB o macOS permite.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

exec .venv/bin/python -u - <<'PY'
import time
import usb.core
import usb.util

def find():
    for pid, name in ((0x0003, "BROM"), (0x2000, "PRELOADER")):
        d = usb.core.find(idVendor=0x0E8D, idProduct=pid)
        if d is not None:
            return d, pid, name
    return None, None, None

print("Aguardando BROM/preloader. Desligue o celular e conecte o cabo.")
dev, pid, mode = None, None, None
while dev is None:
    dev, pid, mode = find()
    if dev is None:
        time.sleep(0.05)

print("Encontrado em modo %s (pid=0x%04x)" % (mode, pid))
print("Device class: 0x%02x" % dev.bDeviceClass)

try:
    cfg = dev.get_active_configuration()
    print("Config:", cfg.bConfigurationValue, "interfaces:", cfg.bNumInterfaces)
    for itf in cfg:
        print("  interface %d  class=0x%02x subclass=0x%02x proto=0x%02x  (driver do macOS?)" % (
            itf.bInterfaceNumber, itf.bInterfaceClass,
            itf.bInterfaceSubClass, itf.bInterfaceProtocol))
except Exception as e:
    print("get_active_configuration ERRO:", repr(e))

def test(name, fn):
    try:
        r = fn()
        n = 0 if r is None else (len(r) if hasattr(r, "__len__") else 1)
        print("%-40s OK (%d bytes)" % (name, n))
    except Exception as e:
        print("%-40s ERRO %r" % (name, e))

test("GET_DESCRIPTOR device", lambda: dev.ctrl_transfer(0x80, 6, 0x0100, 0, 18))

for i in (0, 1):
    def claim(i=i):
        usb.util.claim_interface(dev, i)
        return b"ok"
    test("claim_interface %d" % i, claim)
    test("GET_LINE_CODING interface %d" % i,
         lambda i=i: dev.ctrl_transfer(0xA1, 0x21, 0, i, 7))
    test("SET_LINE_CODING interface %d" % i,
         lambda i=i: dev.ctrl_transfer(0x21, 0x20, 0, i, bytearray([0x00, 0xC2, 0x01, 0x00, 0x00, 0x00, 0x08])))
PY
