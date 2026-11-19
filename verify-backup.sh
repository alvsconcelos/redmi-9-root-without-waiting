#!/usr/bin/env bash
# Confere se o backup esta completo e com assinatura valida.
# Uso: ./verify-backup.sh [backups/<data>]
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

BK="${1:-}"
if [[ -z "$BK" ]]; then
  for d in $(ls -td backups/*/ 2>/dev/null); do
    if [[ -s "${d}boot.img" ]]; then BK="${d%/}"; break; fi
  done
fi

if [[ -z "$BK" || ! -d "$BK" ]]; then
  echo "Nenhum backup encontrado. Rode: sudo -E ./backup.sh"
  exit 1
fi

echo "Backup: $BK"
echo
fail=0

check_size() {
  local f="$BK/$1" min="$2" name="$3"
  if [[ ! -f "$f" ]]; then
    printf '%-16s AUSENTE\n' "$name"; fail=1; return
  fi
  local sz
  sz=$(stat -f%z "$f")
  if (( sz < min )); then
    printf '%-16s SUSPEITO (%s bytes, esperado >= %s)\n' "$name" "$sz" "$min"; fail=1
  else
    printf '%-16s ok (%s bytes)\n' "$name" "$sz"
  fi
}

# tamanhos minimos conservadores
check_size seccfg.bin    1024        seccfg.bin
check_size preloader.bin 1024        preloader.bin
check_size boot.img      1048576     boot.img
check_size vbmeta.img    1024        vbmeta.img
check_size nvram.bin     1024        nvram.bin
check_size nvdata.bin    1024        nvdata.bin
check_size persist.bin   1024        persist.bin

echo
magic() {
  local f="$1" want="$2" name="$3"
  [[ -f "$f" ]] || return 0
  local got
  got=$(head -c 8 "$f" | tr -d '\0')
  if [[ "$got" == "$want"* ]]; then
    printf '%-16s assinatura ok (%s)\n' "$name" "$want"
  else
    printf '%-16s assinatura inesperada: %q\n' "$name" "$got"; fail=1
  fi
}

magic "$BK/boot.img"   "ANDROID!" boot.img
magic "$BK/vbmeta.img" "AVB0"     vbmeta.img

# ---- estrutura do seccfg (V4): preve o que o unlock vai encontrar ----
if [[ -s "$BK/seccfg.bin" ]]; then
  .venv/bin/python - "$BK/seccfg.bin" <<'PY'
import struct, sys
path = sys.argv[1]
data = open(path, "rb").read(4096)
magic, ver, size, lock, verity, sboot, endflag = struct.unpack_from("<IIIIIII", data, 0)
names = {1: "LKS_DEFAULT (locked)", 2: "LKS_MP_DEFAULT (locked)",
         3: "LKS_UNLOCK (unlocked)", 4: "LKS_LOCK (locked)",
         5: "LKS_VERIFIED", 6: "LKS_CUSTOM"}
ok = (magic == 0x4D4D4D4D and endflag == 0x45454545 and size >= 0x3C and size <= 4096)
print("seccfg.bin       magic=%s ver=%d size=0x%x lock_state=%d %s dm_verity=%d"
      % ("MMMM" if magic == 0x4D4D4D4D else hex(magic), ver, size, lock,
         names.get(lock, "desconhecido"), verity))
if ok:
    print("                 estrutura V4 valida -> o mtkclient vai reconhecer (Detected V4 Lockstate)")
else:
    print("                 ESTRUTURA INESPERADA -> nao faca o unlock")
    sys.exit(1)
PY
  (( $? == 0 )) || fail=1
fi

echo
echo "sha256:"
( cd "$BK" && shasum -a 256 *.bin *.img 2>/dev/null )

echo
if (( fail == 0 )); then
  echo "RESULTADO: backup OK. Copie a pasta para pendrive/nuvem e pode seguir."
  exit 0
fi
echo "RESULTADO: backup INCOMPLETO. NAO faca o unlock; rode ./backup.sh de novo."
exit 1
