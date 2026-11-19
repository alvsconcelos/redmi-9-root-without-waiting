# Passo a passo manual (leia inteiro antes de começar)

> Versão curta e na ordem certa: **`COMECE-AQUI.md`**. Este arquivo explica o
> porquê de cada passo.

> Situação agora: **nada foi gravado no seu celular**. O bootloader continua
> travado (`ro.boot.flash.locked = 1`), o sistema está funcionando e os backups
> de segurança vão ser criados antes de qualquer escrita.
>
> O BROM mora na ROM do chip (não é alterável por software). Mesmo num brick de
> software, o aparelho continua aceitando conexão BROM — é o nosso plano B.

> **Importante (já testado):** no macOS o exploit só funciona como root.
> Por isso **todo comando de BROM usa `sudo -E`**. Sem sudo dá
> `[Errno 13] Access denied`, porque o driver CDC da Apple segura a interface 0.

---

## 0. Antes de qualquer coisa

1. **Conta Mi / Find Device**: no celular, entre em Ajustes → Conta Mi → Sair da
   conta (ou pelo menos desative "Localizar dispositivo"). Depois de apagar os
   dados, a proteção de ativação pode pedir a conta antiga.
2. **Fotos/arquivos**: o unlock apaga TUDO. Com o celular ligado e a depuração
   USB ativa, salve o que importa:

   ```bash
   cd redmi-9-root-without-waiting
   mkdir -p ~/mi-backup
   adb pull /sdcard/DCIM ~/mi-backup/
   adb pull /sdcard/Pictures ~/mi-backup/
   adb pull /sdcard/Download ~/mi-backup/
   adb pull /sdcard/WhatsApp ~/mi-backup/
   ```

3. Bateria acima de 50%, cabo bom, **porta USB direta no Mac** (sem hub).

---

## 1. Entrar em BROM (a parte que exige timing)

O BROM fica ativo por **menos de 1 segundo** depois de ligar. Por isso o
mtkclient tem que estar rodando **antes**; ele faz poll a cada 0,1 s e segura o
aparelho no instante em que ele aparece.

- Comando rodando → depois desligue o celular e segure **Vol− + Power** →
  conecte o cabo → solte quando o log andar.
- **Nunca** use Vol+ e Vol− juntos: entra em *factory mode* (menu chinês).
- Se aparecer menu chinês: segure Power ~15 s ou `adb reboot`.

---

## 2. Fase 1 — teste de leitura (seguro)

```bash
sudo -E ./unlock.sh --probe
```

Espere aparecer algo assim:

```
Preloader - BROM mode detected.
Preloader -   CPU: MT6768/MT6769
Preloader -   HW code: 0x707
...
DaHandler - Device is in BROM-Mode. Bypassing security.
Exploitation - Kamakiri Run
Exploitation - Done sending payload...
```

e em seguida a **tabela GPT** (lista de partições).

- Chegou na tabela GPT? **Pode seguir.**
- Parou em `Access denied` / `Error on sending payload`? **Pare.** Rode
  `sudo -E ./diag-brom.sh`. Se `claim_interface 0` continuar dando erro, é o
  driver `AppleUSBCDCACMControl` do macOS segurando a interface 0 do BROM —
  nenhum ajuste de permissão resolve. Vá para o **CAMINHO B** do
  `COMECE-AQUI.md` (Windows, Linux ou VM com passthrough USB).
- Não apareceu nada e voltou ao MIUI? O timing falhou; repita o passo 1.

---

## 3. Fase 2 — backup (somente leitura)

```bash
sudo -E ./backup.sh
```

Cria `backups/<data>/` com:

| Arquivo | Para quê |
|---|---|
| `seccfg.bin` | estado do bootloader (restaurar se algo der errado) |
| `preloader.bin` | recuperação de boot (partição boot1) |
| `boot.img` | boot stock — **é essa que o Magisk vai patch** |
| `vbmeta.img` | verity/verification stock |
| `nvram.bin`, `nvdata.bin`, `persist.bin` | dados de IMEI/calibração |

**Copie essa pasta para um pendrive/nuvem.** Sem ela, recuperar um brick fica
bem mais difícil.

> Se algum arquivo essencial (`seccfg.bin`, `preloader.bin`, `boot.img`,
> `vbmeta.img`) ficar vazio, **não faça o unlock**. Tente de novo.

Confira com:

```bash
./verify-backup.sh backups/<data>
```

Ele valida tamanhos e assinaturas (`ANDROID!` na boot, `AVB0` na vbmeta) e
imprime o sha256. O `unlock.sh` também recusa rodar se essas assinaturas
estiverem erradas.

---

## 4. Fase 3 — desbloquear (em 2 etapas)

O unlock é dividido em duas gravações independentes, cada uma com sua entrada em
BROM. Assim, se a primeira falhar, seus dados **não** são apagados.

### 4a. Destravar (grava só o seccfg)

```bash
sudo -E ./unlock.sh
```

Digite `DESTRAVAR`, depois coloque em BROM (Vol− + Power + cabo). Executa:

```
da seccfg unlock
reset
```

O código do mtkclient (`xflash.py: seccfg()`) lê o `seccfg`, valida o cabeçalho
e aborta se não reconhecer o estado — ele não grava às cegas.

Confira com o celular ligado:

```bash
adb shell getprop ro.boot.flash.locked        # 0
adb shell getprop ro.boot.verifiedbootstate   # orange
```

### 4b. Apagar dados + desativar verity

```bash
sudo -E ./unlock.sh --wipe
```

Digite `APAGAR` e coloque em BROM de novo. Executa:

```
e metadata,userdata,md_udc
da vbmeta 3
reset
```

- A primeira boot leva de 5 a 15 minutos. **Não desconecte durante a escrita.**
- Se travar no logo: reconecte em BROM e rode
  `sudo -E ./mtk multi "e metadata,userdata; da vbmeta 3; reset"`.
- `da vbmeta` lê a partição, aplica o patch e regrava — nada é inventado.

---

## 5. Fase 4 — root (Magisk)

1. Baixe o APK: <https://github.com/topjohnwu/Magisk/releases/latest>
2. Instale e envie a boot stock:

   ```bash
   adb install app-release.apk
   adb push backups/<data>/boot.img /sdcard/Download/
   ```

3. No Magisk: **Instalar → Selecionar e corrigir um arquivo** →
   `Download/boot.img`. **Não** marque "Recovery mode".
4. Puxe a imagem gerada e grave:

   ```bash
   adb pull /sdcard/Download/magisk_patched-XXXXX.img .
   sudo -E ./flash-boot.sh magisk_patched-XXXXX.img
   ```

   (`flash-boot.sh` faz `w boot`, `da vbmeta 3`, `reset` via BROM. Alternativa
   com fastboot: `fastboot flash boot ...` + `fastboot --disable-verity
   --disable-verification flash vbmeta backups/<data>/vbmeta.img`.)

Cada atualização do MIUI remove o root: repatch a boot da versão nova.

---

## 6. Se algo der errado

Sintoma mais comum: **não sai do logo / bootloop**. O bootloader e o BROM
continuam acessíveis, então dá para recuperar:

```bash
# volta boot e vbmeta stock (não mexe em dados)
sudo -E ./restore.sh backups/<data>

# se precisar voltar o estado do bootloader (só com tudo stock!)
sudo -E ./restore.sh backups/<data> --seccfg
```

Regras de ouro:

- **Nunca** rode `da seccfg lock` com boot/recovery modificados → brick.
- Não interrompa o cabo durante `w`/`e`.
- Se um comando de escrita falhar no meio, **pare** e reconecte em BROM para
  restaurar antes de tentar outra coisa.
- `preloader.bin` só deve ser regravado em último caso
  (`sudo -E ./mtk w preloader backups/<data>/preloader.bin --parttype boot1`); um
  preloader errado deixa o aparelho "morto" (mas o BROM ainda responde).

---

## 7. Comandos úteis

```bash
sudo -E ./mtk printgpt                 # só lê a tabela de partições
sudo -E ./mtk devices --filter Xiaomi  # lista suportados
sudo -E ./mtk multi "reset"            # reinicia o aparelho a partir do BROM
sudo -E ./mtk r boot boot.img          # lê uma partição
sudo -E ./mtk w boot boot.img          # grava uma partição
./usb-watch.sh                 # mostra o que está no USB
```

Log detalhado:

```bash
sudo -E ./mtk printgpt --debugmode     # gera log.txt
```
