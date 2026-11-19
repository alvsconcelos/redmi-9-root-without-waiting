# Redmi 9 com bootloader destravado e root, no macOS, sem Mi Unlock

Em novembro de 2026 eu destravei o bootloader e instalei o Magisk num Redmi 9
(`galahad`, MT6768, MIUI 13) usando um MacBook com Apple Silicon e um cabo USB.
Sem Mi Unlock, sem os 7 dias de espera, sem cartão SIM e sem Windows.

Funcionou no meu aparelho. Antes de repetir, leia o aviso lá no fim. É por sua
conta e risco.

[Português](#por-que-eu-fiz-isso) · [English](#english)

## Por que eu fiz isso

Tinha um Redmi 9 parado na gaveta há mais de um ano. Bateria boa, tela inteira,
nenhum uso. Queria transformar ele num servidor pequeno em casa: AdGuard Home e alguns
containers. Um projeto de fim de semana.

Quase tudo isso pede root. E o caminho da Xiaomi é chato por definição: pedir
unlock no Mi Unlock, esperar uma semana, usar o mesmo chip SIM e rodar um
programa que só existe para Windows. No meu caso tinha um detalhe a mais: o
slot do SIM está quebrado. Sem SIM você não passa nem da primeira tela.

Foi então que caiu a ficha. Aquele `MediatekBootloaderUnlock` que circula em
fórum é só uma pasta com o [mtkclient](https://github.com/bkerler/mtkclient)
dentro. Ou seja, dá para fazer a mesma coisa no Mac, direto, sem depender do
Mi Unlock. Só que no macOS o caminho tem umas pedras específicas: o driver CDC
da Apple, o caminho do libusb, o macFUSE e um bug de parsing que me custou uma
tarde. Depois de resolver tudo isso, o aparelho destravou de primeira.

Este repositório é esse fluxo, com os scripts e o que eu aprendi no caminho.
Hoje o Redmi 9 roda 24 horas por dia fazendo o que eu queria.

## O que muda em relação ao Mi Unlock

O Mi Unlock exige conta Mi, chip SIM, Windows e sete dias de espera. Aqui você
precisa de um Mac, um cabo e uns 40 minutos, sendo que a maior parte é backup.

O unlock em si é uma escrita na partição `seccfg`. O mtkclient lê a partição,
confere o cabeçalho e só então grava. Se não reconhecer o formato, ele aborta
sem tocar em nada.

Depois vem o root: patch da `boot` stock com o Magisk e flash via fastboot. É o
procedimento normal do Magisk, nada de especial.

## O que você precisa

- macOS (testei em Apple Silicon; Intel provavelmente funciona)
- Homebrew
- Python 3.11
- libusb e android-platform-tools, os dois saem pelo brew
- cabo USB de dados, de preferência direto no Mac, sem hub
- bateria acima de 50%

O aparelho que usei:

```
Redmi 9 (M2004J19C), codename galahad
MediaTek MT6768 (Helio G80/G85)
MIUI 13 / Android 12, build V13.0.2.0.SJCMIXM
seccfg V4, BROM 0e8d:0003
```

Outros MediaTek com seccfg V3 ou V4 e suporte ao Kamakiri no mtkclient podem
funcionar, mas eu não testei. Se o seu modelo não aparecer em
`./mtk devices --filter <modelo>`, não insista.

## Como rodar

Clone e deixe o `setup.sh` fazer o trabalho chato. Ele instala as dependências,
clona o mtkclient num commit fixo, aplica os patches deste repo e roda o
autoteste.

```bash
git clone https://github.com/alvsconcelos/redmi-9-root-without-waiting
cd redmi-9-root-without-waiting
./setup.sh
```

Daqui para frente, o guia com os sintomas e a ordem exata está no
[COMECE-AQUI.md](COMECE-AQUI.md). Um resumo:

```bash
# com o celular ligado e depuração USB ativa
./check.sh

# teste de leitura, não grava nada
sudo -E ./unlock.sh --probe

# backup, também somente leitura
sudo -E ./backup.sh
./verify-backup.sh backups/<data>

# destravar o bootloader (grava só o seccfg)
sudo -E ./unlock.sh
adb shell getprop ro.boot.flash.locked      # esperado: 0

# opcional: apagar dados e desativar verity
sudo -E ./unlock.sh --wipe

# root
adb install Magisk-v31.1.apk
adb push backups/<data>/boot.img /sdcard/Download/
# no app: Instalar > Selecionar e corrigir um arquivo > Download/boot.img
adb pull /sdcard/Download/magisk_patched-XXXXX.img .
adb reboot bootloader
fastboot flash boot magisk_patched-XXXXX.img
fastboot reboot
```

Copie `backups/<data>` para um pendrive ou para a nuvem antes de qualquer
escrita. Dentro daquela pasta tem IMEI e calibração do aparelho, então ela não
vai para o Git (o `.gitignore` já cuida disso).

### Se você usa um agente de IA

Funciona bem. Abra a pasta no OpenCode, Claude Code, Cursor ou equivalente e
cole:

```text
Leia o COMECE-AQUI.md deste repositório e me guie passo a passo.
Explique cada etapa antes de rodar, confirme o estado do celular via adb e não
rode nada que grave na flash (unlock, wipe, flash, restore) sem eu confirmar.
Se algo falhar, leia PLANO-B.md antes de tentar de novo.
```

O agente roda setup, checagens e backup sozinho. Os botões do celular e o cabo
vão sobrar para você.

## O tropeço que tomou mais tempo

No macOS, o BROM do MediaTek aparece como um dispositivo CDC ACM, e o driver
`AppleUSBCDCACMControl` fica dono da interface 0. O exploit do Kamakiri usa
exatamente essa interface. Sem root, o libusb não consegue tomar o dispositivo
e você leva `[Errno 13] Access denied` no meio do payload.

Com `sudo -E` funciona. Levei um tempo para aceitar que era só isso, porque a
mensagem parece problema de permissão de arquivo e não é.

Se você rodar qualquer comando de BROM sem sudo, o erro volta. Vale para o
probe e para o backup também.

## O que acontece por baixo

O BROM é uma ROM de fábrica dentro do SoC. Ele aparece no USB por menos de um
segundo quando o aparelho liga, por isso o comando precisa estar rodando antes
de você conectar o cabo. O mtkclient fica em loop esperando esse momento.

Quando o BROM responde, o mtkclient aplica o exploit, sobe o DA e passa a ler e
escrever a flash. O unlock grava o `seccfg` (lock state 2 vira 3). O root é o
Magisk de sempre.

Os patches que este repo aplica no mtkclient:

- `Exploit/kamakiri.py`: reutiliza o handle USB já aberto em vez de reabrir
  com `usb.core.find()`
- `Library/mtk_main.py`: `multi "a; b; c"` aceita espaço depois do ponto e
  vírgula; antes o argparse morria no meio do script
- `DA/mtk_da_handler.py` e `Filesystem/mtkdafs.py`: toleram a ausência do
  macFUSE

## O que eu não testei

Não testei em macOS Intel, não testei em outro celular e não testei com outra
versão do MIUI. Também não mexi em IMEI, região nem ROM.

O unlock não remove conta Mi, Find Device ou FRP. Saia da conta no aparelho
antes de apagar os dados, senão a proteção de ativação pode pedir ela depois.

## Se der errado

O pior caso realista é o celular não subir. O BROM é ROM de chip, então o Mac
continua falando com ele, e o `restore.sh` devolve `boot`, `vbmeta` e `seccfg`
a partir do backup.

```bash
sudo -E ./restore.sh backups/<data>
sudo -E ./restore.sh backups/<data> --seccfg
```

Se ainda estiver bootando e você só quer voltar o kernel:

```bash
fastboot flash boot backups/<data>/boot.img
```

O que pode dar errado, em ordem de gravidade: cabo cair no meio da escrita do
`seccfg` (o único ponto realmente sensível), DA não gravar o `seccfg`, MIUI não
subir depois do wipe. Todos têm volta pelo BROM ou pelo fastboot.

Nunca rode `da seccfg lock` com boot ou recovery modificado. Essa é a receita
de brick de verdade.

## Resultado no meu aparelho

```
ro.boot.flash.locked        = 0
ro.boot.verifiedbootstate   = orange
sys.boot_completed          = 1
magiskd                     = rodando como root
```

Os dados continuaram no lugar, 7,6 GB em uso. Não precisei do wipe.

## Arquivos

| Arquivo | Para quê |
|---|---|
| `setup.sh` | dependências, clone do mtkclient, patches |
| `COMECE-AQUI.md` | guia principal, na ordem |
| `PASSO-A-PASSO.md` | versão detalhada |
| `PLANO-B.md` | diagnóstico do macOS e alternativas |
| `unlock.sh` | `--probe`, destravar, `--wipe` |
| `backup.sh` | backup somente leitura |
| `verify-backup.sh` | confere tamanho, assinatura e seccfg |
| `restore.sh` | volta boot, vbmeta e seccfg |
| `flash-boot.sh` | grava boot patchada via BROM |
| `diag-brom.sh` | testa permissão USB do BROM |
| `check.sh` | modelo e SoC via adb |
| `selftest.sh` | valida os comandos sem celular |

## Créditos

O trabalho pesado não é meu.

O [mtkclient](https://github.com/bkerler/mtkclient), do bkerler, faz o
exploit, o DA e toda a conversa com a flash. É GPLv3, e os patches em
`patches/` são derivados dele, então também são GPLv3. O
[Magisk](https://github.com/topjohnwu/Magisk), do topjohnwu, é o root. O
`MediatekBootloaderUnlock` que circula em fórum foi o que me mostrou que o
caminho existia, e por dentro é o mtkclient também.

Os scripts e a documentação deste repo são MIT.

## Aviso

Isto mexe no bootloader e na flash do seu aparelho. Pode dar errado, pode
apagar seus dados, pode deixar o celular sem bootar, pode anular a garantia e,
em teoria, pode inutilizar o aparelho.

Você faz por sua conta e risco. Não me responsabilizo por dano, perda de dados,
aparelho brickado, conta bloqueada nem qualquer outra consequência.

Leia os scripts antes de rodar. Faça backup. Não rode nada que você não
entendeu.

## Licença

Scripts e documentação: [MIT](LICENSE). Os patches em `patches/` seguem
GPLv3, por serem derivados do mtkclient.

---

# English

I had an old Redmi 9 sitting in a drawer and wanted to turn it into a small
home server: AdGuard Home and a couple of containers.
Most of that needs root, and Xiaomi's official route asks for Mi Unlock, a
seven day wait, the same SIM card and a Windows-only tool. My SIM slot is
broken, so that route was closed from the start.

Turns out `MediatekBootloaderUnlock`, the package that circulates in forums, is
just a Windows wrapper around [mtkclient](https://github.com/bkerler/mtkclient).
The same job can be done natively on macOS. This repo is the flow that worked
on my device, with the scripts and the notes I wish I had found.

One warning about the language: the scripts, log messages and the detailed
docs are in **Portuguese**, my native language. The commands are copy-paste
ready, so you can follow along even if you don't read Portuguese. If you want
a guided walkthrough in your own language, use the AI-agent prompt from the
Portuguese section: point the agent at `COMECE-AQUI.md` and it will translate
as it goes.

### What it does

It enters the MediaTek BROM, uses mtkclient to load a DA, dumps a backup of
`seccfg`, `boot`, `vbmeta`, `preloader`, `nvram`, `nvdata` and `persist`, then
writes `seccfg` to unlock the bootloader. Optionally it wipes data and disables
verity. The root step is the ordinary Magisk flow: patch the stock `boot` and
flash it.

### Requirements and quick start

macOS, Homebrew, Python 3.11, libusb, android-platform-tools, a data cable and
a battery above 50%.

```bash
git clone https://github.com/alvsconcelos/redmi-9-root-without-waiting
cd redmi-9-root-without-waiting
./setup.sh
```

Then follow [COMECE-AQUI.md](COMECE-AQUI.md). Short version:

```bash
sudo -E ./unlock.sh --probe
sudo -E ./backup.sh
./verify-backup.sh backups/<data>
sudo -E ./unlock.sh          # writes seccfg
sudo -E ./unlock.sh --wipe   # optional: wipe and disable verity
```

### The macOS part everyone trips on

The BROM enumerates as a CDC ACM device and `AppleUSBCDCACMControl` owns
interface 0, which is the interface the Kamakiri exploit needs. Without root,
libusb cannot claim it and you get `[Errno 13] Access denied` in the middle of
the payload. Run everything with `sudo -E` and it works. That was most of my
debugging time.

### Tested on

```
Redmi 9 (M2004J19C), galahad
MediaTek MT6768 (Helio G80/G85)
MIUI 13 / Android 12, V13.0.2.0.SJCMIXM
```

Other MediaTek devices with seccfg V3 or V4 and Kamakiri support may work. I
only tested this one, on Apple Silicon.

### What it does not do

It does not remove Mi account, Find Device or FRP. It does not repair IMEI,
change region or flash ROMs.

### Safety

The unlock only writes `seccfg`. `preloader`, `lk`, `tee`, `nvram` and
`persist` are never touched. BROM is chip ROM, so even a phone that refuses to
boot can still talk to the Mac, and `restore.sh` brings it back from the
backup. Make the backup first anyway, and never run `da seccfg lock` with a
modified boot image.

### Credits and license

[mtkclient](https://github.com/bkerler/mtkclient) does the exploit, the DA and
all the flash I/O. GPLv3. Patches under `patches/` are derivative works and
therefore GPLv3 too. [Magisk](https://github.com/topjohnwu/Magisk) is the root,
also GPLv3. Scripts and docs here are MIT.

### Disclaimer

This modifies your bootloader and flashes your device. It can fail, wipe your
data, leave the phone unbootable, void the warranty and, in theory, brick it.
You do this at your own risk. I take no responsibility for damage, data loss,
a bricked device, a blocked account or anything else. Read the scripts before
running them, make a backup, and don't run what you don't understand.
