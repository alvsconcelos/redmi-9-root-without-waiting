#!/usr/bin/env bash
# RECUPERACAO: regrava boot/vbmeta stock a partir de um backup (via BROM).
# Uso: ./restore.sh [pasta-do-backup] [--seccfg]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

BK=""
USE_SECCFG=0
for a in "$@"; do
  case "$a" in
    --seccfg) USE_SECCFG=1 ;;
    *) BK="$a" ;;
  esac
done

if [[ -z "$BK" ]]; then
  for d in $(ls -td backups/*/ 2>/dev/null); do
    if [[ -s "${d}boot.img" ]]; then BK="${d%/}"; break; fi
  done
fi

if [[ -z "$BK" || ! -d "$BK" ]]; then
  echo "Nenhum backup completo (com boot.img). Uso: ./restore.sh backups/AAAAMMDD-HHMMSS"
  exit 1
fi

echo "Backup: $BK"
for f in boot.img vbmeta.img; do
  [[ -s "$BK/$f" ]] || { echo "Faltando $BK/$f"; exit 1; }
done
[[ $USE_SECCFG == 1 && ! -s "$BK/seccfg.bin" ]] && { echo "Faltando seccfg.bin"; exit 1; }

PREFIX=""
if [[ $USE_SECCFG == 1 ]]; then
  PREFIX="w seccfg $BK/seccfg.bin; "
fi

cat <<EOF
Vai regravar:
  boot.img
  vbmeta.img
$([[ $USE_SECCFG == 1 ]] && echo "  seccfg.bin (relock! perigoso)")

Deixe rodando e coloque o celular em BROM:
  desligado + Vol- + Power + cabo
EOF
read -r -p 'Digite RESTAURAR para continuar: ' ans
[[ "$ans" == "RESTAURAR" ]] || { echo "Cancelado."; exit 1; }

./mtk multi "${PREFIX}w boot $BK/boot.img; w vbmeta $BK/vbmeta.img; da vbmeta 3; reset"

echo
echo "Se nao reiniciar: desconecte o cabo e segure Power por ~15s."
