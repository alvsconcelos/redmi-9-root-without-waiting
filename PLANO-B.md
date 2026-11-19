# Plano B: quando o macOS não deixa o exploit passar

O `COMECE-AQUI.md` é o caminho normal. Este arquivo existe para o caso de você
rodar `sudo -E ./unlock.sh --probe` e o mtkclient travar antes de chegar ao chip.
Aqui está o que o diagnóstico mostrou, o teste de 30 segundos e as saídas que
funcionam quando o Mac não colabora.

## O que o diagnóstico mostrou

O BROM do Redmi 9 se apresenta no USB como CDC ACM, não como um dispositivo
genérico:

```
Device class: 0x02 (Communications)
interface 0 class=0x02 subclass=0x02 proto=0x01   <- CDC Communication
interface 1 class=0x0a                            <- CDC Data (bulk)
```

No macOS, o driver `AppleUSBCDCACMControl` toma a interface 0 e não devolve.
Quando eu tentei falar com o BROM sem root, a leitura em massa da interface 1
funcionava, mas `claim_interface 0` e as requisições `GET_LINE_CODING` e
`SET_LINE_CODING` voltavam com `EACCES`. A interface 1 também podia ser tomada,
só que line coding nela dá pipe error.

O exploit Kamakiri precisa dessas requisições de controle na interface 0. É
exatamente o que o driver da Apple segura para usuário comum.

Root consegue tomar o dispositivo. Foi o que resolveu aqui: com `sudo -E` o
probe passou, leu a tabela GPT e subiu o DA, com `flashmode: XFLASH` e
`patched: true` no `.state`. Sem root, o macOS nega antes de chegar ao chip.
Por isso todo comando de BROM neste projeto usa `sudo -E`.

Nada foi gravado no celular durante esse diagnóstico. Ele continuou travado e
bootando normal.

## Teste rápido

Com o aparelho em BROM (desligado, Vol− junto com Power, cabo direto no Mac):

```bash
sudo -E ./diag-brom.sh
```

Se aparecer `claim_interface 0 OK`, o problema não é o driver. Siga com o fluxo
normal, `sudo -E ./unlock.sh --probe` e depois o backup.

Se der EACCES mesmo com sudo, o driver da Apple está no caminho e a saída é usar
outro sistema operacional. As três opções abaixo estão em ordem de quanto
trabalho dão.

## Windows, se você tiver acesso a um PC

É o caminho mais curto se já existe um Windows na sua casa. Use o próprio
`MediatekBootloaderUnlock` que circula nos fóruns.

Instale o `UsbDk_1.0.22_x64.msi` que vem na pasta. Desligue o celular, segure
Vol− junto com Power e conecte o cabo. Rode `UnlockBootloader.bat`.

O UsbDk toma o dispositivo do driver de série do Windows, que é a mesma coisa
que falta no macOS. O comando dentro do `.bat` é o nosso `da seccfg unlock`.

## Linux ou Raspberry Pi

Também resolve, e é a opção que eu recomendo se você tem um Raspberry Pi
parado. O udev do Linux dá permissão ao dispositivo sem precisar de sudo em
tudo, então o comportamento é mais previsível que no Mac.

```bash
sudo apt install git python3-pip libusb-1.0-0
git clone https://github.com/bkerler/mtkclient
cd mtkclient
pip3 install -r requirements.txt
sudo cp Setup/Linux/*.rules /etc/udev/rules.d/
sudo udevadm control -R && sudo udevadm trigger
```

Depois de reiniciar a sessão:

```bash
sudo python3 mtk.py printgpt     # deixe esperando e conecte em BROM
sudo python3 mtk.py da seccfg unlock
sudo python3 mtk.py e metadata,userdata,md_udc
sudo python3 mtk.py da vbmeta 3
sudo python3 mtk.py reset
```

Os scripts deste repo também rodam lá. Copie `backup.sh`, `unlock.sh`,
`flash-boot.sh`, o `mtk` e a pasta `backups/`, porque os comandos são os mesmos.

Um live USB de Ubuntu em qualquer PC x86 serve, sem instalar nada no disco.

## VM com passthrough USB no Mac

Funciona, com uma ressalva importante: UTM e QEMU não servem. Eles usam o libusb
do host e batem no mesmo bloqueio do macOS.

Parallels Desktop e VMware Fusion capturam o dispositivo no nível do
hipervisor, então o driver CDC da Apple fica fora do caminho. O VMware Fusion
tem licença gratuita para uso pessoal.

Crie uma VM Ubuntu ARM64 ou Windows 11 ARM, instale o mtkclient dentro dela e
conecte o aparelho em BROM pelo menu de USB da VM. O BROM fica ativo por menos
de um segundo, então deixe o `mtk.py printgpt` rodando na VM antes de plugar o
cabo.

## O que não fazer

Não rode `da seccfg lock` com boot ou recovery alterados. Não tente forçar o
unlock com o aparelho bootado no MIUI. E não apague dados antes de ter um backup
que passou no `verify-backup.sh`.

## Recuperação

Com o backup em mãos, qualquer susto se resolve pelo BROM:

```bash
sudo -E ./restore.sh backups/<data>            # boot e vbmeta stock
sudo -E ./restore.sh backups/<data> --seccfg   # estado do bootloader, só com tudo stock
```
