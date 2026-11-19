# Passo a passo detalhado

O `COMECE-AQUI.md` é a versão curta. Este arquivo explica o porquê de cada
etapa, para você saber o que está fazendo em vez de só copiar comando.

Até você rodar o unlock, nada é gravado no aparelho. O bootloader continua
travado, o sistema funciona e o backup é criado antes de qualquer escrita.

O BROM mora na ROM do chip, então não dá para perdê-lo com software. Mesmo num
brick, o Mac volta a conversar com o aparelho. É por isso que a recuperação
existe.

## 0. Antes de tudo

O unlock não remove conta Mi nem Find Device. Se a conta ficar no aparelho, a
proteção de ativação pode pedir ela depois de um wipe. Saia da conta em
Ajustes, Conta Mi, Sair da conta, ou pelo menos desative "Localizar
dispositivo".

Se você for apagar os dados, salve as fotos antes. Com o celular ligado e a
depuração USB ativa:

```bash
mkdir -p ~/mi-backup
adb pull /sdcard/DCIM      ~/mi-backup/
adb pull /sdcard/Pictures  ~/mi-backup/
adb pull /sdcard/Download  ~/mi-backup/
adb pull /sdcard/WhatsApp  ~/mi-backup/
```

Bateria acima de 50%, cabo que transmite dados e uma porta USB direto no Mac.
Hub USB é fonte de dor de cabeça nesse tipo de operação.

## 1. Entrar em BROM

O BROM fica ativo por menos de um segundo depois de ligar. O mtkclient tem que
estar rodando antes, porque ele faz poll a cada 0,1 segundo e segura o
aparelho no instante em que ele aparece.

Com o comando esperando: desligue o celular de verdade, segure Vol− e Power,
conecte o cabo e solte os botões quando o log andar.

Vol+ com Vol− ao mesmo tempo abre o factory mode no `galahad`, aquele menu
chinês que aparece como `0e8d:200e`. Para sair, segure Power por uns 15
segundos.

Se o celular voltar ao MIUI, o timing falhou. Repita.

## 2. Teste de leitura

```bash
sudo -E ./unlock.sh --probe
```

O log esperado:

```
Preloader - BROM mode detected.
Preloader -   CPU: MT6768/MT6769
Preloader -   HW code: 0x707
DaHandler - Device is in BROM-Mode. Bypassing security.
Exploitation - Kamakiri Run
Exploitation - Done sending payload...
DAXFlash - DA SLA is disabled
DAXFlash - Boot to succeeded.
GPT Table:
```

Chegou na tabela GPT, pode seguir. Parou em `Access denied` ou `Error on
sending payload`, pare e rode `sudo -E ./diag-brom.sh`. Se o
`claim_interface 0` continuar falhando mesmo com sudo, é o driver da Apple e o
caminho passa a ser o `PLANO-B.md`.

Sem sudo o erro é garantido. O exploit precisa tomar a interface 0 do BROM, e
só root consegue isso no macOS.

## 3. Backup

```bash
sudo -E ./backup.sh
```

A pasta `backups/<data>/` fica com `seccfg.bin` (8 MB), `preloader.bin` (4 MB),
`boot.img` (64 MB), `vbmeta.img` (8 MB), `nvram.bin` e `nvdata.bin` (64 MB
cada) e `persist.bin` (48 MB).

Para que serve cada um: o seccfg guarda o estado do bootloader, o preloader é a
recuperação de boot (partição boot1), o boot é a imagem stock que o Magisk vai
patchar, o vbmeta guarda verity e verification, e os três últimos têm IMEI e
calibração.

```bash
./verify-backup.sh backups/<data>
```

O verify confere tamanho, assinatura e a estrutura do seccfg, e imprime o
sha256 de tudo. Só siga se terminar com `backup OK`. O `unlock.sh` também se
recusa a rodar se as assinaturas estiverem erradas.

Copie a pasta para um pendrive ou para a nuvem. Sem ela, recuperar um brick
fica bem mais difícil. E não publique: tem IMEI ali dentro.

## 4. Destravar o bootloader

O unlock é dividido em duas gravações independentes, cada uma com sua entrada
em BROM. Se a primeira falhar, seus dados não são apagados.

Primeiro, só o seccfg:

```bash
sudo -E ./unlock.sh
```

Digite `DESTRAVAR` e entre em BROM. Ele roda `da seccfg unlock` e `reset`.

O código do mtkclient lê o seccfg, exige o cabeçalho `MMMM`, identifica se é V3
ou V4 e aborta se não reconhecer o estado. Ele não grava às cegas.

Confira com o celular ligado:

```bash
adb shell getprop ro.boot.flash.locked        # 0
adb shell getprop ro.boot.verifiedbootstate   # orange
```

Depois, se quiser apagar os dados e desativar verity:

```bash
sudo -E ./unlock.sh --wipe
```

Digite `APAGAR` e entre em BROM de novo. Ele apaga `metadata`, `userdata` e
`md_udc`, roda `da vbmeta 3` e reinicia.

O `da vbmeta` lê a partição, aplica o patch e regrava. Nada é inventado. O
primeiro boot depois do wipe leva de 5 a 15 minutos, e não é anormal ele passar
um tempo parado no logo.

No meu aparelho o wipe não foi necessário. O MIUI subiu normalmente depois do
unlock, com os dados intactos. Deixei a etapa separada justamente para você
escolher.

## 5. Root

Baixe o APK do Magisk, instale e mande a boot stock para o celular:

```bash
adb install Magisk-v31.1.apk
adb push backups/<data>/boot.img /sdcard/Download/
```

No app, cartão Magisk, Instalar, "Selecionar e corrigir um arquivo" e escolha
`Download/boot.img`. Não marque "Recovery mode": esse aparelho tem ramdisk na
boot, então é o modo normal.

```bash
adb pull /sdcard/Download/magisk_patched-XXXXX.img .
adb reboot bootloader
fastboot flash boot magisk_patched-XXXXX.img
fastboot reboot
```

Pelo BROM também funciona: `sudo -E ./flash-boot.sh
magisk_patched-XXXXX.img`.

Cada atualização do MIUI remove o root. Na próxima, extraia a boot da versão
nova e patche de novo.

## 6. Se algo der errado

O sintoma mais comum é não sair do logo. O bootloader e o BROM continuam
acessíveis, então tem volta:

```bash
# volta boot e vbmeta stock, sem mexer nos dados
sudo -E ./restore.sh backups/<data>

# volta também o estado do bootloader, só com tudo stock
sudo -E ./restore.sh backups/<data> --seccfg
```

Com fastboot disponível, `fastboot flash boot backups/<data>/boot.img` é mais
rápido para o caso de bootloop depois do Magisk.

Regras que valem a pena:

Não rode `da seccfg lock` com boot ou recovery modificados. É a receita de
brick de verdade. Não interrompa o cabo durante `w` ou `e`. Se um comando de
escrita falhar no meio, pare, reconecte em BROM e restaure antes de tentar
qualquer outra coisa.

O `preloader.bin` só deve ser regravado em último caso, com
`sudo -E ./mtk w preloader backups/<data>/preloader.bin --parttype boot1`. Um
preloader errado deixa o aparelho morto, mas o BROM ainda responde.

## 7. Comandos úteis

```bash
sudo -E ./mtk printgpt                 # lê a tabela de partições
sudo -E ./mtk devices --filter Xiaomi  # lista modelos suportados
sudo -E ./mtk multi "reset"            # reinicia pelo BROM
sudo -E ./mtk r boot boot.img          # lê uma partição
sudo -E ./mtk w boot boot.img          # grava uma partição
./usb-watch.sh                         # mostra o que aparece no USB
```

Para gerar log detalhado:

```bash
sudo -E ./mtk printgpt --debugmode     # cria log.txt
```
