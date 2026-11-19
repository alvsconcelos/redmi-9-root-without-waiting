#!/usr/bin/env bash
# Grava uma boot.img (de preferencia patchada pelo Magisk) via BROM.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

IMG="${1:-}"
if [[ -z "$IMG" || ! -f "$IMG" ]]; then
  echo "Uso: ./flash-boot.sh caminho/para/magisk_patched-xxxxx.img"
  exit 1
fi

cat <<EOF
============================================================
 GRAVAR BOOT (Magisk) - partition boot
============================================================
Imagem: $IMG

Deixe este comando rodando e SO DEPOIS coloque o celular em BROM:
  1) Desligue o celular de verdade (nao reinicie).
  2) Segure Vol- + Power (NAO use Vol+ e Vol- juntos).
  3) Conecte o cabo direto no Mac.
  4) Solte os botoes quando o log comecar a andar.

Vai executar: w boot <imagem>; da vbmeta 3; reset
Nao desconecte o cabo durante a gravacao.
============================================================
EOF
read -r -p "Pressione ENTER para comecar a esperar o BROM (Ctrl+C para sair)..."

./mtk multi "w boot $IMG; da vbmeta 3; reset"

echo
echo "Pronto. Se nao reiniciar, desconecte o cabo e segure Power por ~15s."
echo "Dica: instale o app Magisk antes, para ele finalizar a configuracao no 1o boot."
