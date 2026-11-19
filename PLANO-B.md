# Plano B — quando o macOS bloqueia o exploit

> Guia curto e na ordem certa: **`COMECE-AQUI.md`**. Este arquivo é o
> diagnóstico + as alternativas (Windows, Linux, VM).

## O que o diagnóstico mostrou

O BROM do Redmi 9 se apresenta como **CDC ACM**:

```
Device class: 0x02 (Communications)
interface 0 class=0x02 subclass=0x02 proto=0x01   <- CDC Communication
interface 1 class=0x0a                            <- CDC Data (bulk)
```

No macOS, o driver nativo **AppleUSBCDCACMControl** toma a interface 0. Resultado:

| Operação | Resultado |
|---|---|
| handshake/leitura bulk (interface 1) | OK |
| `claim_interface 0` | **EACCES** |
| `GET/SET_LINE_CODING` na interface 0 | **EACCES** |
| `claim_interface 1` | OK |
| line coding na interface 1 | Pipe error |

O exploit Kamakiri precisa exatamente de `GET_LINE_CODING`/control requests na
interface 0. O driver da Apple segura essa interface para usuários comuns, mas
**root consegue tomar o dispositivo** — foi o que resolveu: com `sudo -E` o
probe passou, leu a GPT e subiu o DA (`flashmode: XFLASH`, `patched: true`).

Sem root o macOS nega **antes** de chegar ao chip. No macOS, então:
**sempre `sudo -E`**.

**Nada foi gravado no celular.** Ele continua travado e bootando normal.

## Teste rápido (30 s)

```bash
sudo -E ./diag-brom.sh
```

Coloque em BROM (Vol− + Power + cabo). Se aparecer `claim_interface 0 OK`, siga
com os comandos normais (`sudo -E ./unlock.sh --probe`, etc). Se der EACCES
**mesmo com sudo**, é o driver da Apple e só outro sistema operacional resolve.

## Opções que funcionam

### 1. PC Windows (mais simples se tiver acesso)

Use o próprio `MediatekBootloaderUnlock` que você baixou:

1. Instale `UsbDk_1.0.22_x64.msi` (está na pasta).
2. Desligue o celular, segure Vol− + Power, conecte o cabo.
3. Rode `UnlockBootloader.bat`.

O UsbDk "sequestra" o dispositivo do driver de série do Windows, exatamente o
que falta no macOS. O comando do .bat equivale ao nosso `da seccfg unlock`.

### 2. PC Linux / Raspberry Pi (recomendado)

```bash
sudo apt install git python3-pip libusb-1.0-0
git clone https://github.com/bkerler/mtkclient
cd mtkclient
pip3 install -r requirements.txt
sudo cp Setup/Linux/*.rules /etc/udev/rules.d/
sudo udevadm control -R && sudo udevadm trigger
# reinicie a sessão
sudo python3 mtk.py printgpt     # deixe esperando e conecte em BROM
sudo python3 mtk.py da seccfg unlock
sudo python3 mtk.py e metadata,userdata,md_udc
sudo python3 mtk.py da vbmeta 3
sudo python3 mtk.py reset
```

Se quiser, copie os arquivos deste projeto (`backup.sh`, `unlock.sh`,
`flash-boot.sh`, `mtk` e a pasta `backups/`) — os comandos são os mesmos.

Live USB do Ubuntu num PC x86 também serve (não precisa instalar nada).

### 3. VM com passthrough USB no Mac (Parallels ou VMware Fusion)

- **UTM/QEMU não serve**: ele usa libusb no host e bate no mesmo bloqueio.
- **Parallels Desktop** e **VMware Fusion** (gratuito para uso pessoal) capturam
  o dispositivo no nível do hipervisor, então o driver CDC da Apple não atrapalha.
- Crie uma VM **Ubuntu ARM64** (ou Windows 11 ARM), instale o mtkclient dentro
  dela e conecte o aparelho em BROM usando o menu de USB da VM.
- O timing do BROM (menos de 1 s) exige deixar o `mtk.py printgpt` rodando na VM
  **antes** de conectar o cabo.

## O que NÃO fazer

- Não rode `da seccfg lock` com boot/recovery alterado.
- Não tente "forçar" o unlock com o aparelho bootado normal.
- Não apague dados antes de ter o backup (`backup.sh`) funcionando.

## Recuperação

Com backups em mãos, qualquer susto se resolve por BROM:

```bash
./restore.sh backups/<data>            # boot + vbmeta stock
./restore.sh backups/<data> --seccfg   # estado do bootloader (só tudo stock)
```
