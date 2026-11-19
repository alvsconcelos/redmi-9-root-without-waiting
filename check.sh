#!/usr/bin/env bash
# Identifica modelo/SoC (com o celular ligado e depuracao USB ativada).
set -uo pipefail

if ! command -v adb >/dev/null 2>&1; then
  echo "adb nao encontrado. Instale com: brew install android-platform-tools"
  exit 1
fi

if ! adb get-state >/dev/null 2>&1; then
  cat <<'EOF'
Nenhum aparelho via adb.
- Ative Opcoes do desenvolvedor > Depuracao USB.
- Conecte o cabo e aceite a autorizacao na tela do celular.
EOF
  exit 1
fi

for p in ro.product.device ro.product.model ro.board.platform ro.hardware \
         ro.build.version.release ro.miui.ui.version.name ro.build.version.incremental; do
  printf '%-32s %s\n' "$p" "$(adb shell getprop "$p" | tr -d '\r')"
done

echo
case "$(adb shell getprop ro.product.device | tr -d '\r')" in
  lancelot|galahad) echo "Redmi 9 / 9 Prime (Helio G80, MT6768) -> compativel com este metodo." ;;
  cattail)  echo "Redmi 9 India (Helio G35, MT6765) -> compativel com este metodo." ;;
  dandelion|angelica) echo "Redmi 9A/9C (MTK) -> compativel com este metodo." ;;
  lemon|lime) echo "Redmi 9T (Snapdragon) -> NAO e MediaTek; mtkclient nao serve." ;;
  *) echo "Modelo nao reconhecido. Confira se o SoC e MediaTek (ro.board.platform = mt6xxx)." ;;
esac
