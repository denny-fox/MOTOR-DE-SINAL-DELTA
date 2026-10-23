# MOTOR-DE-SINAL-DELTA

Aplicacao Flutter para analise estatistica de futebol, com armazenamento local SQLite e foco em validacao e controlo de risco. O app rejeita competicoes identificadas como SRL ou simuladas.

## MVP atual

- Cadastro de partidas, competicao, data e gols esperados informados manualmente.
- Probabilidades 1X2, mais de 2,5 gols e ambas marcam por distribuicoes de Poisson independentes.
- Sinais T01-T05 com limiares fixos da versao inicial.
- Registro local do resultado final.
- Painel, lista de partidas e visualizacao dos sinais ativos.
- Importacao de partidas por arquivos CSV ou JSON, com validacao, transacao atomica e deduplicacao.
- Backtest walk-forward cronologico com Brier score e faixas de calibracao 1X2.

As probabilidades dependem somente das estimativas digitadas pelo usuario. Nao ha integracao com dados ao vivo, recomendacao de apostas ou garantia de resultado. Os limiares dos sinais sao iniciais e precisam ser avaliados antes de qualquer uso operacional.

O ajuste walk-forward usa os resultados anteriores para corrigir probabilidades 1X2 e nunca usa o resultado da partida avaliada. Partidas com o mesmo horario recebem a mesma calibracao historica, evitando que um resultado seja usado para prever outra partida simultanea. Brier score e calibracao sao descritivos; qualidade e volume da base historica continuam determinantes.

O calculo Poisson inclui massa suficiente da cauda da distribuicao (tolerancia de `1e-12`) e valida gols esperados finitos entre 0 e 10.

### Formato de importacao

CSV exige cabecalho com `competition,home_team,away_team,home_xg,away_xg,kickoff,home_score,away_score`. Os placares podem ficar vazios para jogos sem resultado. `kickoff` deve ser ISO 8601; gols esperados aceitam valores de 0 a 10.

JSON aceita uma lista de objetos com os mesmos nomes de campo ou um objeto com a propriedade `matches` contendo essa lista. Partidas SRL/simuladas, placares incompletos e linhas invalidas sao rejeitados; a importacao inteira e cancelada se houver erro.

## Executar

As pastas nativas Android e iOS estao incluidas. Se forem recriadas, gere o esqueleto com Flutter; depois instale as dependencias:

```sh
flutter create --platforms=android,ios .
flutter pub get
flutter test
flutter run
```

Para validar antes de executar:

```sh
flutter analyze
flutter test
```

Para gerar o APK Android de depuracao, use `flutter build apk --debug`; o arquivo fica em `build/app/outputs/flutter-apk/app-debug.apk`. A compilacao Android requer Android SDK 36. Para executar ou compilar no iOS, e necessario macOS com Xcode; o projeto usa deployment target iOS 15.

O backtest usa somente as partidas com resultado que estiverem na base local. Importe uma base historica representativa para avaliar Brier score e calibracao; resultados de amostras pequenas nao validam os sinais nem seus limiares. O app nao consulta fontes externas e nao obtem automaticamente jogos ou estimativas de gols esperados.
