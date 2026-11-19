# COMECE AQUI

Guia na ordem certa, do zero ao root, no macOS.

> Se você é um agente de IA lendo isto: siga exatamente esta ordem, rode as
> checagens por conta própria e **peça confirmação humana antes de qualquer
> etapa que grave na flash** (`unlock.sh`, `unlock.sh --wipe`, `flash-boot.sh`,
> `fastboot flash`, `restore.sh`). Se algo divergir do esperado, pare e leia
> `PLANO-B.md`.

---

## Regras de ouro

1. **Backup primeiro.** Sem `backups/<data>/` com `seccfg.bin`, `boot.img` e
   `vbmeta.img`, não faça o unlock.
2. **`sudo -E` em tudo que fala com o BROM.** Sem root o macOS nega a
   interface 0 (`[Errno 13] Access denied`).
3. **Não desconecte o cabo** durante `Write:`/`Writing`.
4. **Nunca** rode `da seccfg lock` com boot/recovery modificado.
5. Se algo der errado: pare, desconecte, segure Power ~15 s, recomece.

---

## 0. Preparar

```bash
git clone https://github.com/alvsconcelos/redmi-9-root-without-waiting
cd redmi-9-root-without-waiting
./setup.sh
```

No celular (ligado, uso normal):

- ative **Opções do desenvolvedor → Depuração USB** e autorize o Mac;
- saia da **conta Mi** / desative "Localizar dispositivo" (o unlock não remove
  conta Mi; se sobrar conta, a proteção de ativação pode pedir ela depois);
- salve fotos/arquivos que importam (se for fazer o wipe opcional):

```bash
mkdir -p ~/mi-backup
adb pull /sdcard/DCIM      ~/mi-backup/
adb pull /sdcard/Pictures  ~/mi-backup/
adb pull /sdcard/Download  ~/mi-backup/
adb pull /sdcard/WhatsApp  ~/mi-backup/
```

Confira o aparelho:

```bash
./check.sh
```

Esperado: `ro.board.platform = mt6768` e modelo `galahad` (Redmi 9).

---

## 1. Como entrar em BROM (a parte que exige timing)

O BROM fica ativo por **menos de 1 segundo** ao ligar. Por isso o comando tem
que estar rodando **antes**.

1. Deixe o comando rodando no Mac (ele fica em `Waiting for PreLoader VCOM`).
2. Desligue o celular **de verdade** (não reinicie).
3. Segure **Vol− + Power**.
4. Conecte o cabo **direto no Mac** (sem hub).
5. Solte os botões quando o log começar a andar.

- **Nunca** use Vol+ e Vol− juntos: no Redmi 9 isso entra em *factory mode*
  (menu chinês, `0e8d:200e`). Se acontecer: segure Power ~15 s.
- Se nada aparecer e o celular voltar ao MIUI: o timing falhou, repita.
- O BROM aparece como `0e8d:0003` (ou preloader `0e8d:2000`, que também serve).

---

## 2. Teste de leitura (não grava nada)

```bash
sudo -E ./unlock.sh --probe
```

Esperado:

```
Preloader - BROM mode detected.
Exploitation - Kamakiri Run
Exploitation - Done sending payload...
DAXFlash - DA SLA is disabled
DAXFlash - Boot to succeeded.
GPT Table:
```

- Chegou na tabela GPT? Siga.
- `Access denied`? Rode `sudo -E ./diag-brom.sh` e leia `PLANO-B.md`.

---

## 3. Backup (somente leitura)

```bash
sudo -E ./backup.sh
./verify-backup.sh backups/<data>
```

O `verify` precisa terminar com `RESULTADO: backup OK`. Ele confere tamanho,
assinatura (`ANDROID!`, `AVB0`) e a estrutura do `seccfg` (V3/V4, lock state).

**Copie para fora do Mac:**

```bash
cp -R backups/<data> ~/Desktop/
# e para um pendrive/nuvem
sudo chown -R "$(id -u):$(id -g)" backups hwparam.json .state
```

---

## 4. Destravar o bootloader (etapa 1)

```bash
sudo -E ./unlock.sh
```

Digite `DESTRAVAR` e entre em BROM. Executa **só**:

```text
da seccfg unlock
reset
```

Nada mais é gravado: dados, `boot` e `vbmeta` ficam intactos.

Depois, com o celular ligado:

```bash
adb shell getprop ro.boot.flash.locked        # esperado: 0
adb shell getprop ro.boot.verifiedbootstate   # esperado: orange
```

- `0` / `orange` → pode seguir.
- Continuou `1` → **pare**, não rode a etapa 2.

---

## 5. Wipe (opcional)

O MIUI normalmente sobe sem apagar nada depois do unlock — foi o que aconteceu
comigo (dados intactos). Só faça o wipe se quiser o aparelho limpo ou se o
sistema começar a se comportar mal.

```bash
sudo -E ./unlock.sh --wipe
```

Digite `APAGAR` e entre em BROM. Executa:

```text
e metadata,userdata,md_udc
da vbmeta 3
reset
```

> Isso apaga **tudo**. Primeiro boot: 5–15 min, pode ficar parado no logo.

---

## 6. Root (Magisk)

```bash
# 1. instale o app (baixe em github.com/topjohnwu/Magisk/releases)
adb install Magisk-v31.1.apk

# 2. mande a boot stock para o celular
adb push backups/<data>/boot.img /sdcard/Download/
```

No app **Magisk**:

1. cartão **Magisk** → **Instalar**;
2. **Selecionar e corrigir um arquivo**;
3. escolha `Download/boot.img`;
4. **não** marque "Recovery mode";
5. espere gerar `Download/magisk_patched-XXXXX.img`.

Depois:

```bash
adb pull /sdcard/Download/magisk_patched-XXXXX.img .
adb reboot bootloader
fastboot flash boot magisk_patched-XXXXX.img
fastboot reboot
```

Alternativa sem fastboot (via BROM): `sudo -E ./flash-boot.sh magisk_patched-XXXXX.img`.

Confira:

```bash
adb shell "ps -A | grep magiskd"        # deve aparecer magiskd como root
adb shell "su -c id"                    # aprova o pedido na tela do celular
```

Se der bootloop:

```bash
fastboot flash boot backups/<data>/boot.img
fastboot reboot
```

---

## 7. Se algo der errado

| Sintoma | O que fazer |
|---|---|
| Não sai do logo | `sudo -E ./restore.sh backups/<data>` (BROM) ou `fastboot flash boot backups/<data>/boot.img` |
| Bootloop após Magisk | idem |
| Bootloader em estado estranho | `sudo -E ./restore.sh backups/<data> --seccfg` (só com boot stock) |
| Menu chinês na tela | factory mode, não é brick: segure Power ~15 s |
| BROM não aparece | outro cabo/porta, sem hub; tente conectar sem botão nenhum |
| `Access denied` | `sudo -E` + `./diag-brom.sh` + `PLANO-B.md` |

O `restore.sh` se recusa a rodar sem backup válido — proteção, não bug.
O BROM é ROM de fábrica: mesmo sem boot, o Mac fala com o aparelho.

**Nunca** rode `da seccfg lock` com boot/recovery modificado.

---

## Mapa dos arquivos

| Arquivo | Para quê |
|---|---|
| `setup.sh` | instala dependências + mtkclient + patches |
| `unlock.sh --probe` | teste de leitura |
| `backup.sh` | backup somente leitura |
| `verify-backup.sh` | valida o backup (tamanho, assinatura, seccfg) |
| `unlock.sh` | etapa 1: destrava (grava seccfg) |
| `unlock.sh --wipe` | etapa 2: apaga dados + desativa verity |
| `restore.sh` | volta boot/vbmeta/seccfg do backup |
| `flash-boot.sh` | grava boot patchada via BROM |
| `diag-brom.sh` | testa permissão USB do BROM (30 s) |
| `check.sh` | identifica modelo/SoC via adb |
| `selftest.sh` | valida os comandos offline (sem celular) |
| `usb-watch.sh` | mostra o que aparece no USB |
| `PASSO-A-PASSO.md` | versão detalhada, com explicações |
| `PLANO-B.md` | diagnóstico do macOS e alternativas |
