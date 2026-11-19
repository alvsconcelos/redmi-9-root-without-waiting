#!/usr/bin/env bash
# Valida, OFFLINE (sem celular), o parsing de todos os comandos "multi"
# usados pelos scripts. Foi assim que descobrimos o bug do espaco depois do ';'.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -d mtkclient || ! -x .venv/bin/python ]]; then
  echo "Nada para testar ainda: rode ./setup.sh primeiro."
  exit 0
fi

export PYTHONPATH="$PWD/mtkclient${PYTHONPATH:+:$PYTHONPATH}"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

exec .venv/bin/python - <<'PY'
import contextlib
import io
import re
import shlex
import sys
import glob

sys.path.insert(0, "mtkclient")
import mtk  # noqa: E402

captured = {}


class DummyMain:
    """Substitui mtk.Main: pega o parser e nao conecta no aparelho."""

    def __init__(self, args):
        self.args = args

    def run(self, parser):
        captured["parser"] = parser
        return 0


mtk.Main = DummyMain
sys.argv = ["mtk.py", "printgpt"]
mtk.main()
parser = captured["parser"]

subs = {
    "$OUT": "backups/20260101-000000",
    "${OUT}": "backups/20260101-000000",
    "$BK": "backups/20260101-000000",
    "${BK}": "backups/20260101-000000",
    "$IMG": "magisk_patched.img",
    "${IMG}": "magisk_patched.img",
    "$PREFIX": "w seccfg backups/20260101-000000/seccfg.bin; ",
    "${PREFIX}": "w seccfg backups/20260101-000000/seccfg.bin; ",
}

pattern = re.compile(r'multi\s+"([^"]+)"')
total = 0
fail = 0

for script in sorted(glob.glob("*.sh")):
    text = open(script, encoding="utf-8").read()
    for m in pattern.finditer(text):
        raw = m.group(1)
        for k, v in subs.items():
            raw = raw.replace(k, v)
        print(f"\n{script}:")
        for part in [p.strip() for p in raw.split(";") if p.strip()]:
            total += 1
            argv = shlex.split(part)
            try:
                with contextlib.redirect_stderr(io.StringIO()):
                    ns = parser.parse_args(argv)
                extra = ""
                if getattr(ns, "cmd", "") == "da":
                    extra = f"  (subcmd={getattr(ns, 'subcmd', None)})"
                print(f"  ok   {part}{extra}")
            except SystemExit:
                fail += 1
                print(f"  ERRO {part}")

print(f"\n{total - fail}/{total} comandos validos.")
if fail:
    print("Corrija os comandos acima antes de rodar com o celular.")
    sys.exit(1)
print("Parsing OK. (Isso valida a camada de argumentos, nao a gravacao.)")
PY
