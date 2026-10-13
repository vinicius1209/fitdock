# FitDock

Passos e últimos batimentos da Galaxy Fit3 na barra de menus do Mac.

```
Fit3 ──BT──▶ Samsung Health ──▶ Health Connect ──▶ FitDock (Android) ──Wi-Fi──▶ FitDock (Mac)
```

- **Android** (`android/`): lê passos, distância, calorias e batimentos no Health Connect
  e envia ao Mac. A cada resposta o Mac diz quando mandar de novo: 45 s enquanto alguém
  olha o painel ou pediu atualização, 3 min fora disso (um periódico de 15 min fica de
  rede de segurança). Acha o Mac sozinho por Bonjour (`_fitdock._tcp`); dá pra fixar o
  endereço na tela do app.
- **Mac** (`mac/`): recebe em `http://<mac>:47800/v1/snapshot` (só escrita, exige o código
  de pareamento), guarda o último envio em `~/Library/Application Support/FitDock/` e
  mostra passos e batimento na barra de menus (sem ícone no Dock). O clique abre um
  painel com anéis, coração que pulsa no ritmo do último bpm, gráfico do dia, botão de
  atualizar e preferências. Os números ficam apagados depois de 2 h sem envio.

Os dados não passam por nenhum servidor: só celular e Mac, na rede de casa.

## Build

```sh
# Mac: gera mac/Build/FitDock.app; --install copia para /Applications
cd mac && ./scripts/build-app.sh --install

# Android: precisa de JDK 17 a 24 (o Gradle 8.14 não roda no JDK 25)
cd android
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
# Pareamento sem digitar: passa o código que aparece no Mac
adb shell am start -n dev.vinimachado.fitdock/.MainActivity --es code XXXXXX
```

## Limites conhecidos

- O batimento mais recente depende da cadeia inteira: a Fit3 sincroniza com o Samsung
  Health, que escreve no Health Connect quando quer. Atrasos de 30 a 60 minutos são normais.
  Abrir o Samsung Health no celular força a sincronização com a pulseira.
- Calorias totais do Samsung Health no Health Connect podem não bater com o que o app da
  Samsung mostra (problema conhecido do lado da Samsung).
- **Segundo plano precisa de bateria "Sem restrições"** (botão na tela do app Android).
  Sem isso, com o celular bloqueado o Android corta a rede do app (APP_BACKGROUND) e os
  envios param. As tarefas não declaram condição de rede de propósito: na Samsung o app
  congelado fica com a rede negada (OEM_DENY) e o agendador nunca dispararia a tarefa.
- O app do Mac precisa estar aberto para receber. Ligue "Abrir ao iniciar sessão" nas
  preferências.
