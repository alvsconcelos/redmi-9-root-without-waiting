#!/usr/bin/env bash
# FASE 1 (somente leitura): salva particoes criticas via BROM.
# Nao escreve nada no aparelho. Seguro.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

OUT="backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

cat <<'EOF'
============================================================
 BACKUP VIA BROM (SOMENTE LEITURA) - Redmi 9 galahad
============================================================
Deixe este comando rodando e SO DEPOIS coloque o celular em BROM:

  1) Desligue o celular de verdade (nao reinicie).
  2) Segure Vol- + Power.
  3) Conecte o cabo direto no Mac.
  4) Solte os botoes quando o log comecar a andar.

Nao use Vol+ e Vol- juntos (entra em factory mode / menu chines).
============================================================
EOF

./mtk multi "printgpt; r seccfg $OUT/seccfg.bin; r preloader $OUT/preloader.bin --parttype boot1; r boot $OUT/boot.img; r vbmeta $OUT/vbmeta.img; r nvram $OUT/nvram.bin; r nvdata $OUT/nvdata.bin; r persist $OUT/persist.bin; reset"

echo
echo "Arquivos em $OUT:"
ls -lh "$OUT"
echo
for f in seccfg.bin preloader.bin boot.img vbmeta.img; do
  if [[ ! -s "$OUT/$f" ]]; then
    echo "ATENCAO: $f vazio/ausente. NAO prossiga para o unlock."
  fi
done
echo
echo "COPIE a pasta $OUT para outro lugar (pendrive/nuvem) antes de continuar."
echo "Depois confira com:  ./verify-backup.sh $OUT"
echo "Se o verify disser OK, pode rodar:  sudo -E ./unlock.sh"
