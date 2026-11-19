#!/usr/bin/env bash
# Instala tudo o que este projeto precisa no macOS:
#   - libusb, android-platform-tools, Python 3.11
#   - clone do mtkclient num commit fixo + patches deste repo
#   - venv com as dependencias
# Uso: ./setup.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

MTK_REPO="https://github.com/bkerler/mtkclient.git"
MTK_COMMIT="118a000a83ea31c4f427fe5225abfe964546e05e"
PATCH="$PWD/patches/0001-macos-fixes.patch"

info() { printf '\n==> %s\n' "$*"; }
warn() { printf 'aviso: %s\n' "$*"; }
die()  { printf 'erro: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "este setup foi escrito para macOS (testado em Apple Silicon)."
command -v git >/dev/null 2>&1 || die "instale o git (xcode-select --install)."

if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew nao encontrado. Instale em https://brew.sh e rode de novo."
fi

info "dependencias do sistema"
brew list libusb >/dev/null 2>&1 || brew install libusb
command -v adb >/dev/null 2>&1 || brew install android-platform-tools

info "Python"
PY=""
for c in python3.11 python3.12 python3.13 python3; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
    PY="$c"; break
  fi
done
[[ -n "$PY" ]] || { brew install python@3.11; PY="python3.11"; }
echo "usando: $PY ($($PY -V 2>&1))"

info "mtkclient"
if [[ ! -d mtkclient ]]; then
  git clone "$MTK_REPO" mtkclient
else
  echo "mtkclient/ ja existe, reaproveitando."
fi

git -C mtkclient fetch --quiet origin 2>/dev/null || warn "nao consegui atualizar o clone (seguindo offline)."
git -C mtkclient checkout --quiet "$MTK_COMMIT" \
  || die "commit $MTK_COMMIT nao encontrado no mtkclient."

if git -C mtkclient apply --reverse --check "$PATCH" >/dev/null 2>&1; then
  echo "patches de macOS: ja aplicados."
elif git -C mtkclient apply --check "$PATCH" >/dev/null 2>&1; then
  git -C mtkclient apply "$PATCH"
  echo "patches de macOS: aplicados."
else
  die "nao consegui aplicar patches/0001-macos-fixes.patch.

Se voce mexeu no mtkclient manualmente, rode:
  git -C mtkclient checkout -- .
e depois este setup de novo."
fi

info "ambiente Python (.venv)"
[[ -d .venv ]] || "$PY" -m venv .venv
.venv/bin/pip install --upgrade pip --quiet
.venv/bin/pip install --quiet -r mtkclient/requirements.txt

info "permissao de execucao"
chmod +x ./*.sh mtk mtk-gui 2>/dev/null || true

info "autoteste (offline, sem celular)"
if ./selftest.sh; then
  ok=1
else
  ok=0
fi

cat <<'EOF'

============================================================
 SETUP CONCLUIDO
============================================================
Proximo passo (leia COMECE-AQUI.md antes):

  ./check.sh                      # com o celular ligado + depuracao USB
  sudo -E ./unlock.sh --probe     # teste SOMENTE LEITURA

Lembretes:
  - todo comando de BROM precisa de "sudo -E" no macOS;
  - para entrar em BROM: celular desligado + Vol- + Power + cabo;
  - NAO use Vol+ e Vol- juntos (entra em factory mode);
  - backup primeiro, unlock depois.

Se algo falhar, leia PLANO-B.md.
EOF

[[ "$ok" == "1" ]] || die "o autoteste falhou (veja a saida acima)."
