#!/usr/bin/env bash
# Desbloqueio em 2 etapas (cada uma exige uma entrada em BROM):
#   ./unlock.sh         -> ETAPA 1: grava seccfg (destrava o bootloader)
#   ./unlock.sh --wipe  -> ETAPA 2: apaga dados + desativa verity/verification
#   ./unlock.sh --probe -> teste somente leitura
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

BANNER() { echo "============================================================"; }

# ---------------------------------------------------------------- probe
if [[ "${1:-}" == "--probe" ]]; then
  BANNER
  echo " TESTE DE LEITURA (BROM) - nao grava nada"
  BANNER
  cat <<'EOF'
Deixe este comando rodando e SO DEPOIS coloque o celular em BROM:
  1) Desligue o celular de verdade (nao reinicie).
  2) Segure Vol- + Power.
  3) Conecte o cabo direto no Mac.
  4) Solte os botoes quando o log andar.

Esperado: "BROM mode detected", "Kamakiri Run" e a tabela GPT.
Se parar em "Access denied"/"Error on sending payload", pare e me avise.
============================================================
EOF
  exec ./mtk printgpt
fi

# ------------------------------------------------------------ backup
BK=""
if [[ "${1:-}" == "--wipe" ]]; then
  BK="${2:-}"
elif [[ -n "${1:-}" ]]; then
  BK="$1"
fi

if [[ -z "$BK" ]]; then
  for d in $(ls -td backups/*/ 2>/dev/null); do
    if [[ -s "${d}boot.img" ]]; then BK="${d%/}"; break; fi
  done
fi

if [[ -z "$BK" || ! -s "$BK/seccfg.bin" || ! -s "$BK/boot.img" || ! -s "$BK/vbmeta.img" ]]; then
  cat <<'EOF'
Backup incompleto (precisa de seccfg.bin + boot.img + vbmeta.img).
Rode primeiro:  sudo -E ./backup.sh
Confira com:    ./verify-backup.sh
EOF
  exit 1
fi

if [[ "$(head -c 8 "$BK/boot.img")" != "ANDROID!" || "$(head -c 4 "$BK/vbmeta.img")" != "AVB0" ]]; then
  cat <<EOF
Backup com assinatura invalida em boot.img ou vbmeta.img.
Rode:  ./verify-backup.sh $BK
e, se preciso, refaca:  sudo -E ./backup.sh
EOF
  exit 1
fi

BROM_HELP() {
  cat <<'EOF'
Deixe este comando rodando e SO DEPOIS coloque o celular em BROM:
  1) Desligue o celular de verdade (nao reinicie).
  2) Segure Vol- + Power (nunca Vol+ e Vol- juntos).
  3) Conecte o cabo direto no Mac.
  4) Solte os botoes quando o log comecar a andar.
EOF
}

# --------------------------------------------------------------- etapa 2
if [[ "${1:-}" == "--wipe" ]]; then
  LOCKED="$(adb shell getprop ro.boot.flash.locked 2>/dev/null | tr -d '\r' || true)"

  BANNER
  echo " ETAPA 2/2 - APAGAR DADOS + DESATIVAR VERITY"
  BANNER
  cat <<EOF
Backup: $BK
Estado do bootloader agora: ${LOCKED:-desconhecido}

Vai executar:
  e metadata,userdata,md_udc   (APAGA TODOS OS DADOS)
  da vbmeta 3                  (desativa verity/verification)
  reset

Antes disso, confirme no celular ligado:
  adb shell getprop ro.boot.flash.locked   -> deve ser 0

EOF
  BROM_HELP
  echo "============================================================"
  read -r -p 'Para confirmar, digite APAGAR: ' ans
  [[ "$ans" == "APAGAR" ]] || { echo "Cancelado."; exit 1; }

  ./mtk multi "e metadata,userdata,md_udc; da vbmeta 3; reset"

  cat <<'EOF'

Pronto. Se nao reiniciar: desconecte o cabo e segure Power por ~15s.
A primeira boot pode levar 5-15 minutos.
EOF
  exit 0
fi

# --------------------------------------------------------------- etapa 1
BANNER
echo " ETAPA 1/2 - GRAVAR SECCFG (DESTRAVAR BOOTLOADER)"
BANNER
cat <<EOF
Backup usado: $BK

Vai executar apenas:
  da seccfg unlock     (grava a particao seccfg)
  reset

Nada mais e gravado nesta etapa: dados, boot e vbmeta ficam intactos.
Se o celular nao reiniciar: desconecte o cabo e segure Power por ~15s.

EOF
BROM_HELP
echo "============================================================"
read -r -p 'Para confirmar, digite DESTRAVAR: ' ans
[[ "$ans" == "DESTRAVAR" ]] || { echo "Cancelado."; exit 1; }

./mtk multi "da seccfg unlock; reset"

cat <<'EOF'

Etapa 1 concluida. Ligue o celular e confira o estado:

  adb shell getprop ro.boot.flash.locked     # esperado: 0
  adb shell getprop ro.boot.verifiedbootstate # esperado: orange

Se deu 0/orange  -> rode a etapa 2:  sudo -E ./unlock.sh --wipe
Se continuar 1    -> NAO rode a etapa 2. Mande o log para analise.
EOF
