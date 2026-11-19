# Redmi 9 — bootloader destravado + root no macOS, sem Mi Unlock e sem chip SIM

> Desbloqueei o bootloader e instalei o Magisk num **Redmi 9 (`galahad`, MT6768,
> MIUI 13 / Android 12)** usando só um **Mac Apple Silicon** e um cabo USB.
> Sem Mi Unlock, sem esperar 7 dias, sem cartão SIM e sem Windows.
>
> Funcionou no meu aparelho, de ponta a ponta. **Use por sua conta e risco** —
> leia o [aviso](#aviso--disclaimer) antes de começar.

[Português](#a-história) · [English](#english)

---

## A história

Eu tinha um Redmi 9 velho parado na gaveta. Sem uso, bateria ainda boa, e eu
queria transformar ele em uma coisinha útil em casa: um servidorzinho para
rodar AdGuard Home, uns containers, um painel de monitoramento — enfim, aquele
projeto de fim de semana.

Só que quase tudo que eu queria exige **root**. E o caminho oficial da Xiaomi
é: pedir o unlock no Mi Unlock, esperar 7 dias, usar o mesmo chip SIM e rodar
um programinha que só existe para Windows. No meu caso tinha um detalhe: **o
slot do SIM está quebrado**. Sem SIM, o Mi Unlock nem começa.

Foi aí que descobri que o tal `MediatekBootloaderUnlock` que circula por aí é
só uma **embalagem Windows do [mtkclient](https://github.com/bkerler/mtkclient)**.
Ou seja: dava para fazer a mesma coisa no Mac, direto, sem depender do Mi
Unlock. O problema é que no macOS o caminho tem algumas pedras específicas (o
driver CDC da Apple, a versão do libusb, o macFUSE, um bug de parsing...).
Passei um tempo debugando e cheguei num fluxo que funcionou de primeira no
aparelho.

Este repositório é esse fluxo, empacotado e documentado, para quem tem o mesmo
problema — especialmente quem tem só um Mac e um celular MediaTek antigo.

Depois do root, o Redmi 9 virou exatamente o que eu queria: um servidor de
casa, rodando 24/7, custando zero.

---

## O que tem aqui

| | Mi Unlock oficial | Este projeto |
|---|---|---|
| Espera de 7 dias | sim | **não** |
| Precisa de chip SIM | sim | **não** |
| Precisa de Windows | sim | **não** (macOS nativo) |
| Conta Mi | obrigatória | não |
| Apaga seus dados | sim | **opcional** (neste fluxo, não precisou) |
| Root (Magisk) | manual depois | incluído |

O que o projeto faz, na prática:

1. entra no **BROM** do chip (o modo de recuperação de fábrica da MediaTek);
2. sobe um **DA** (download agent) com o mtkclient para conversar com a flash;
3. salva um **backup** das partições críticas (`seccfg`, `boot`, `vbmeta`,
   `preloader`, `nvram`, `nvdata`, `persist`);
4. grava o `seccfg` para **destravar o bootloader**;
5. (opcional) apaga os dados e desativa verity/verification;
6. instala o **Magisk** patchando a `boot` stock.

---

## Requisitos

- **Mac** (testado em Apple Silicon; Intel deve funcionar, não testei)
- **Homebrew**
- **Python 3.11** (`brew install python@3.11`) — o `setup.sh` avisa se faltar
- **libusb** (`brew install libusb`)
- **adb / fastboot** (`brew install android-platform-tools`)
- Cabo USB de dados, de preferência **direto no Mac** (sem hub)
- Bateria acima de **50%**

Aparelho testado:

```
Redmi 9 (M2004J19C) — codename galahad
SoC: MediaTek MT6768 (Helio G80/G85)
MIUI 13 / Android 12 — V13.0.2.0.SJCMIXM
seccfg V4, BROM 0e8d:0003
```

Outros MediaTek com `seccfg` V3/V4 e suporte ao exploit Kamakiri no mtkclient
provavelmente funcionam — mas **só testei nesse**.

---

## Começando

### Caminho 1 — com um agente de IA (o mais fácil)

Se você usa OpenCode, Claude Code, Cursor ou similar, clone o repo, abra a
pasta no agente e cole isto:

```text
Leia o arquivo COMECE-AQUI.md deste repositório e me guie passo a passo.
Explique cada etapa antes de rodar, confirme o estado do meu celular via adb e
NÃO rode nenhuma etapa destrutiva (unlock/wipe/flash) sem eu confirmar.
Se algo falhar, leia PLANO-B.md antes de tentar de novo.
```

O agente consegue rodar o `setup.sh`, os backups e as checagens por você; o que
ele **não** consegue fazer é apertar os botões do celular e trocar o cabo —
essas partes ele vai te pedir.

### Caminho 2 — manual

```bash
git clone https://github.com/alvsconcelos/redmi-9-root-without-waiting
cd redmi-9-root-without-waiting
./setup.sh
```

O `setup.sh` instala as dependências, clona o mtkclient num commit fixo,
aplica os patches de macOS deste repo e roda o autoteste.

Depois, na ordem:

```bash
# 0. com o celular ligado e depuração USB ativa
./check.sh

# 1. teste somente leitura (não grava nada)
sudo -E ./unlock.sh --probe

# 2. backup das partições críticas (somente leitura)
sudo -E ./backup.sh
./verify-backup.sh backups/<data>
# COPIE backups/<data> para fora do Mac!

# 3. destravar o bootloader (grava só o seccfg)
sudo -E ./unlock.sh              # digite DESTRAVAR
adb shell getprop ro.boot.flash.locked        # esperado: 0

# 4. OPCIONAL: apagar dados + desativar verity
sudo -E ./unlock.sh --wipe       # digite APAGAR

# 5. root
adb install Magisk-v31.1.apk
adb push backups/<data>/boot.img /sdcard/Download/
#    no app Magisk: Instalar > Selecionar e corrigir um arquivo > Download/boot.img
adb pull /sdcard/Download/magisk_patched-XXXXX.img .
adb reboot bootloader
fastboot flash boot magisk_patched-XXXXX.img
fastboot reboot
```

> **No macOS, `sudo -E` é obrigatório em tudo que fala com o BROM.** Sem root,
> o libusb não consegue tomar a interface 0 do BROM do driver CDC da Apple e
> você recebe `[Errno 13] Access denied`. Isso foi o que mais me custou tempo.

Se travar em algum ponto: **[`COMECE-AQUI.md`](COMECE-AQUI.md)** tem o passo a
passo com os sintomas, e **[`PLANO-B.md`](PLANO-B.md)** tem o diagnóstico e as
alternativas (Windows, Linux, VM).

---

## Como funciona (resumo técnico)

- O **BROM** é uma ROM de fábrica dentro do SoC. Ele aparece no USB como
  `0e8d:0003` por menos de um segundo ao ligar o aparelho — por isso o
  mtkclient precisa estar rodando **antes** de você conectar o cabo.
- No macOS, esse BROM se apresenta como **CDC ACM**, e o driver
  `AppleUSBCDCACMControl` segura a interface 0. O exploit Kamakiri usa
  justamente essa interface. Com `sudo`, o libusb consegue tomar o dispositivo
  (sem sudo: `EACCES`).
- O `mtkclient` aplica o exploit, sobe o DA e passa a ler/escrever a flash.
- O unlock em si é uma escrita na partição **`seccfg`** (lock state `2` →
  `3`). O mtkclient lê, valida o cabeçalho `MMMM` e aborta se não reconhecer —
  ele não grava às cegas.
- O root é o fluxo normal do Magisk: patch da `boot` stock + `fastboot flash`.

Patches aplicados ao mtkclient (em `patches/0001-macos-fixes.patch`):

| Arquivo | Correção |
|---|---|
| `Exploit/kamakiri.py` | reutiliza o handle USB já aberto em vez de reabrir com `usb.core.find()` |
| `Library/mtk_main.py` | `multi "a; b; c"` aceita espaço depois do `;` (antes o argparse abortava no meio) |
| `DA/mtk_da_handler.py` | tolera ausência do macFUSE |
| `Filesystem/mtkdafs.py` | tolera ausência do macFUSE |

---

## O que este projeto **não** faz

- Não remove **conta Mi / Find Device / FRP**. Saia da conta Mi no celular
  antes de apagar os dados.
- Não conserta IMEI, não troca região, não instala ROM.
- Não garante funcionar em outros modelos — só testei no Redmi 9 `galahad`.

---

## Scripts

| Arquivo | O que faz |
|---|---|
| `setup.sh` | instala dependências, clona o mtkclient, aplica patches |
| `COMECE-AQUI.md` | guia principal, na ordem certa |
| `PASSO-A-PASSO.md` | versão detalhada, com explicações |
| `PLANO-B.md` | diagnóstico do macOS + alternativas (Windows/Linux/VM) |
| `unlock.sh --probe` | teste de leitura (não grava nada) |
| `backup.sh` | backup somente leitura das partições críticas |
| `verify-backup.sh` | confere tamanho, assinatura e estrutura do `seccfg` |
| `unlock.sh` | etapa 1: grava o `seccfg` (destrava) |
| `unlock.sh --wipe` | etapa 2 (opcional): apaga dados + desativa verity |
| `restore.sh` | volta `boot`/`vbmeta` (e `seccfg`) do backup |
| `flash-boot.sh` | grava uma `boot` patchada via BROM |
| `diag-brom.sh` | testa permissões USB do BROM em 30 s |
| `check.sh` | identifica modelo/SoC via adb |
| `selftest.sh` | valida os comandos offline (sem celular) |
| `usb-watch.sh` | mostra o que aparece no USB |
| `mtk` | atalho para o mtkclient com o Python/libusb certos |

---

## Segurança: o que pode dar errado

| Operação | Risco | Se falhar |
|---|---|---|
| gravar `seccfg` | bootloader em estado estranho | `sudo -E ./restore.sh <backup> --seccfg` |
| apagar `metadata`/`userdata`/`md_udc` | perde os dados (era o objetivo) | o sistema recria |
| gravar `vbmeta` | verity inconsistente → não boota | `sudo -E ./restore.sh <backup>` |
| gravar `boot` (Magisk) | bootloop | `sudo -E ./restore.sh <backup>` ou `fastboot flash boot <boot stock>` |
| `preloader` / `lk` | **não são tocados** | — |

O unlock **não** mexe em `preloader`, `lk`, `tee`, `nvram` nem `persist`. E o
BROM é ROM do chip: mesmo que o aparelho não ligue, o Mac volta a falar com ele.
O pior caso realista é "não sobe até você rodar o restore", não brick
permanente. Ainda assim: **backup primeiro, sempre.**

**Nunca** rode `da seccfg lock` com boot/recovery modificado. É a forma mais
fácil de brickar de verdade.

---

## Resultado no meu aparelho

```
ro.boot.flash.locked        = 0
ro.boot.verifiedbootstate   = orange
sys.boot_completed          = 1
magiskd                     = rodando como root
```

Os dados continuaram intactos (7,6 GB em uso) — não precisei do wipe.

---

## Perguntas frequentes

**Preciso apagar os dados?**
Não necessariamente. O caminho oficial costuma pedir, mas neste aparelho o
MIUI subiu normalmente depois do unlock. O wipe ficou como etapa opcional.

**Funciona no macOS Intel?**
Provavelmente. O `setup.sh` detecta `/usr/local` e `/opt/homebrew`. Não testei.

**Funciona em outro celular MediaTek?**
Talvez. Precisa de `seccfg` V3/V4 e suporte ao exploit no mtkclient. Verifique
com `./mtk devices --filter <modelo>`. Se não estiver na lista, não force.

**Por que precisa de `sudo`?**
Porque o driver CDC da Apple toma a interface 0 do BROM, e só root consegue
tomar o dispositivo do driver. Sem isso: `Access denied`.

**Vou perder o root na próxima atualização do MIUI?**
Sim. Atualize, extraia a nova `boot`, patche de novo com o Magisk e grave.

**Isso remove a conta Mi / Find Device?**
Não. Saia da conta no celular antes de apagar os dados.

---

## Créditos

Este projeto é só a cola em volta de ferramentas de outras pessoas:

- **[bkerler/mtkclient](https://github.com/bkerler/mtkclient)** — o motor de
  tudo: exploit Kamakiri, DA, leitura/escrita da flash. Licença GPLv3.
- **[topjohnwu/Magisk](https://github.com/topjohnwu/Magisk)** — o root. GPLv3.
- **MediatekBootloaderUnlock** (o pacote Windows com `UsbDk` +
  `UnlockBootloader.bat`) — foi o que me mostrou que o caminho existia; por
  dentro é o mtkclient.
- Comunidade Xiaomi/MTK pelos vários fóruns sobre BROM, `seccfg` e Kamakiri.

Os patches deste repo (`patches/`) são derivados do mtkclient e portanto
seguem GPLv3. Os scripts e a documentação são MIT.

---

## Aviso / Disclaimer

**AS IS. SEM GARANTIA DE NENHUM TIPO.**

Isto mexe no bootloader e na flash do seu aparelho. Pode dar errado, pode
apagar seus dados, pode deixar o celular sem bootar, pode anular a garantia e
pode (em teoria) inutilizar o aparelho. **Você faz por sua conta e risco.**
Não me responsabilizo por danos, perda de dados, aparelho brickado, conta
bloqueada ou qualquer outra consequência.

Leia todos os scripts antes de rodar. Faça backup. Não rode nada que você não
entende.

---

## Licença

Scripts e documentação: [MIT](LICENSE).
Patches em `patches/`: GPLv3 (derivados do mtkclient).

---

# English

## Unlocking the Redmi 9 bootloader and rooting it on macOS — no Mi Unlock, no SIM card

I had an old Redmi 9 sitting in a drawer and wanted to turn it into a small
home server (AdGuard Home, a couple of containers, a monitoring dashboard).
Almost everything I wanted needs **root**, and Xiaomi's official path requires
Mi Unlock, a 7-day wait, the same SIM card, and a Windows-only tool. My SIM
slot is broken, so that route was closed.

The `MediatekBootloaderUnlock` package that circulates online is just a Windows
wrapper around **[mtkclient](https://github.com/bkerler/mtkclient)**. So the
same job can be done natively on macOS. It took some debugging (the Apple CDC
driver, libusb paths, macFUSE, a parsing bug), and this repo is the working
flow, packaged and documented.

> **Portuguese only, on purpose:** the scripts, log messages and documentation
> are written in **pt-BR** (that's my native language). The **commands are
> copy-paste ready** and do not depend on the language. If you don't read
> Portuguese, use the AI-agent prompt below — it will walk you through
> everything in your language.

### What it does

1. Enters the MediaTek **BROM** mode (`0e8d:0003`).
2. Uses **mtkclient** to load a DA and talk to the flash.
3. Dumps a **backup** of `seccfg`, `boot`, `vbmeta`, `preloader`, `nvram`,
   `nvdata`, `persist`.
4. Writes **`seccfg`** to unlock the bootloader (lock state `2` → `3`).
5. *(optional)* wipes data and disables verity/verification.
6. Installs **Magisk** by patching the stock `boot` image.

### Requirements

- macOS (tested on Apple Silicon; Intel probably works)
- Homebrew, Python 3.11, libusb, `android-platform-tools` (adb/fastboot)
- USB data cable, straight into the Mac (no hub), battery above 50%

Tested device:

```
Redmi 9 (M2004J19C) — codename galahad
MediaTek MT6768 (Helio G80/G85)
MIUI 13 / Android 12 — V13.0.2.0.SJCMIXM
```

Other MediaTek devices with `seccfg` V3/V4 and Kamakiri support in mtkclient
*may* work. I only tested this one.

### Quick start

```bash
git clone https://github.com/alvsconcelos/redmi-9-root-without-waiting
cd redmi-9-root-without-waiting
./setup.sh
```

Then follow **[`COMECE-AQUI.md`](COMECE-AQUI.md)** (Portuguese, but mostly
commands). Short version:

```bash
sudo -E ./unlock.sh --probe      # read-only test
sudo -E ./backup.sh              # read-only backup
./verify-backup.sh backups/<data>
sudo -E ./unlock.sh              # stage 1: unlock (writes seccfg)
sudo -E ./unlock.sh --wipe       # stage 2 (optional): wipe + disable verity
# Magisk: patch boot.img in the app, then
fastboot flash boot magisk_patched-XXXXX.img
```

### The macOS gotcha

**Everything that talks to BROM must run as root (`sudo -E`).** The BROM
enumerates as a CDC ACM device and `AppleUSBCDCACMControl` owns interface 0.
Without root, libusb cannot claim it and you get `[Errno 13] Access denied`.
With `sudo`, it works. This was 90% of the debugging.

### What it does not do

- Does not remove Mi account / Find Device / FRP.
- Does not repair IMEI, change region or flash ROMs.
- No guarantee for other models.

### Safety

The unlock only writes `seccfg`. `preloader`, `lk`, `tee`, `nvram` and
`persist` are never touched. **BROM is chip ROM** — even if the phone refuses
to boot, the Mac can still talk to it and `restore.sh` can bring it back.
Still: **make the backup first**, and never run `da seccfg lock` with a
modified boot image.

### Credits

- **[bkerler/mtkclient](https://github.com/bkerler/mtkclient)** — GPLv3. The
  exploit, the DA, all the flash I/O. This repo is mostly glue.
- **[topjohnwu/Magisk](https://github.com/topjohnwu/Magisk)** — GPLv3. Root.
- **MediatekBootloaderUnlock** (Windows bundle) — showed the path existed.
- Xiaomi/MTK community forums for BROM, `seccfg` and Kamakiri knowledge.

Patches in `patches/` are derivative works of mtkclient and therefore GPLv3.
Scripts and docs are MIT.

### Disclaimer

**AS IS. NO WARRANTY OF ANY KIND.** This modifies your bootloader and flashes
your device. It can fail, wipe your data, leave the phone unbootable, void your
warranty, and (in theory) brick it. **You do this at your own risk.** I take no
responsibility for any damage, data loss, bricked device, blocked account or
any other consequence. Read the scripts before running them. Make a backup.
