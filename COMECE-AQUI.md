# COMECE AQUI

A ordem certa, do zero ao root, no macOS.

Se você é um agente de IA lendo isto: siga a ordem, rode as checagens sozinho e
peça confirmação antes de qualquer coisa que grave na flash (`unlock.sh`,
`--wipe`, `flash-boot.sh`, `fastboot flash`, `restore.sh`). Se algo divergir do
esperado, pare e leia o `PLANO-B.md`.

## Antes de qualquer comando

Backup primeiro. Sem uma pasta `backups/<data>/` com `seccfg.bin`, `boot.img` e
`vbmeta.img`, não se faz o unlock.

Tudo que fala com o BROM precisa de `sudo -E`. Sem root o macOS nega a
interface 0 e você leva `[Errno 13] Access denied`. Não é falta de permissão de
arquivo, é o driver CDC da Apple segurando o dispositivo.

Não desconecte o cabo enquanto aparecer `Write:` ou `Writing`.

Nunca rode `da seccfg lock` com boot ou recovery modificado.

Se algo der errado, desconecte, segure Power por uns 15 segundos e recomece.

## Preparar

```bash
git clone https://github.com/alvsconcelos/redmi-9-root-without-waiting
cd redmi-9-root-without-waiting
./setup.sh
```

No celular, com ele ligado e em uso normal: ative Opções do desenvolvedor,
ligue a Depuração USB e autorize o Mac. Saia da conta Mi ou pelo menos desative
"Localizar dispositivo", porque o unlock não remove conta Mi e a proteção de
ativação pode pedir ela depois.

Se você pretende apagar os dados mais tarde, salve o que importa agora:

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

Você quer ver `ro.board.platform = mt6768` e o modelo `galahad`.

## Entrar em BROM

O BROM fica ativo por menos de um segundo quando o aparelho liga, então o
comando tem que estar rodando antes.

Deixe o comando esperando no Mac, desligue o celular de verdade (não reinicie),
segure Vol− junto com Power, conecte o cabo direto no Mac, sem hub, e solte os
botões quando o log começar a andar.

Vol+ e Vol− ao mesmo tempo não entram em BROM no Redmi 9. Isso abre o factory
mode, aquele menu chinês com VID `0e8d:200e`. Se acontecer, segure Power por 15
segundos e o aparelho volta.

Se nada aparecer e o MIUI subir de novo, o timing falhou. Repita.

## Teste de leitura

```bash
sudo -E ./unlock.sh --probe
```

O log bom passa por `BROM mode detected`, `Kamakiri Run`, `DA SLA is
disabled`, `Boot to succeeded` e termina na tabela GPT com todas as partições.

Se parar em `Access denied`, rode `sudo -E ./diag-brom.sh` e leia o
`PLANO-B.md` antes de tentar outra coisa.

## Backup

```bash
sudo -E ./backup.sh
./verify-backup.sh backups/<data>
```

O verify precisa terminar com `RESULTADO: backup OK`. Ele confere tamanho,
assinatura (`ANDROID!` na boot, `AVB0` na vbmeta) e a estrutura do seccfg.

Copie a pasta para fora do Mac:

```bash
cp -R backups/<data> ~/Desktop/
sudo chown -R "$(id -u):$(id -g)" backups hwparam.json .state
```

Dentro da pasta tem IMEI e calibração do aparelho. Não publique isso.

## Destravar o bootloader

```bash
sudo -E ./unlock.sh
```

Digite `DESTRAVAR` e entre em BROM. Essa etapa grava só o seccfg e reinicia.
Dados, boot e vbmeta ficam como estão.

Com o celular ligado:

```bash
adb shell getprop ro.boot.flash.locked        # 0
adb shell getprop ro.boot.verifiedbootstate   # orange
```

Se o primeiro continuar 1, pare e não rode a etapa seguinte.

## Apagar os dados (opcional)

No meu aparelho o MIUI subiu sem apagar nada, com os 7,6 GB de dados no lugar.
Só faça o wipe se quiser o aparelho limpo ou se o sistema começar a se
comportar mal.

```bash
sudo -E ./unlock.sh --wipe
```

Digite `APAGAR` e entre em BROM. Isso apaga `metadata`, `userdata` e `md_udc`,
desativa verity e reinicia. O primeiro boot leva de 5 a 15 minutos e pode ficar
parado no logo um tempo.

## Root

Baixe o APK do Magisk em github.com/topjohnwu/Magisk/releases, instale e mande
a boot stock para o celular:

```bash
adb install Magisk-v31.1.apk
adb push backups/<data>/boot.img /sdcard/Download/
```

No app, abra o cartão Magisk, toque em Instalar, escolha "Selecionar e corrigir
um arquivo" e pegue `Download/boot.img`. Não marque "Recovery mode". Ele gera
um `magisk_patched-XXXXX.img` na mesma pasta.

```bash
adb pull /sdcard/Download/magisk_patched-XXXXX.img .
adb reboot bootloader
fastboot flash boot magisk_patched-XXXXX.img
fastboot reboot
```

Se preferir não usar fastboot, dá para gravar pelo BROM com
`sudo -E ./flash-boot.sh magisk_patched-XXXXX.img`.

Conferir:

```bash
adb shell "ps -A | grep magiskd"
adb shell "su -c id"
```

O `su` pede autorização na tela do celular.

Se entrar em bootloop, volte a boot stock e reinicie:

```bash
fastboot flash boot backups/<data>/boot.img
fastboot reboot
```

## Se algo der errado

Se não sair do logo, rode `sudo -E ./restore.sh backups/<data>` pelo BROM. Se
ainda tiver fastboot, `fastboot flash boot backups/<data>/boot.img` resolve
mais rápido.

Se o bootloader ficar num estado estranho, `sudo -E ./restore.sh
backups/<data> --seccfg` devolve o seccfg original. Só faça isso com boot
stock.

Menu chinês na tela não é brick, é factory mode. Power por 15 segundos.

Se o BROM não aparecer, troque de cabo ou de porta, tire o hub, e tente
conectar sem apertar botão nenhum.

O `restore.sh` se recusa a rodar sem backup válido. É proteção, não bug. E o
BROM é ROM de fábrica: mesmo sem boot, o Mac continua falando com o aparelho.

## Arquivos

- `setup.sh`: dependências, clone do mtkclient e patches
- `unlock.sh --probe`: teste de leitura
- `backup.sh`: backup somente leitura
- `verify-backup.sh`: valida tamanho, assinatura e seccfg
- `unlock.sh`: etapa 1, grava o seccfg
- `unlock.sh --wipe`: etapa 2, apaga dados e desativa verity
- `restore.sh`: volta boot, vbmeta e seccfg
- `flash-boot.sh`: grava boot patchada pelo BROM
- `diag-brom.sh`: testa a permissão USB em 30 segundos
- `check.sh`: modelo e SoC via adb
- `selftest.sh`: valida os comandos sem celular
- `usb-watch.sh`: mostra o que aparece no USB
- `PASSO-A-PASSO.md`: a versão detalhada, com explicações
- `PLANO-B.md`: diagnóstico do macOS e alternativas
