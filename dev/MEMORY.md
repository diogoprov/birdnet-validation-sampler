# Memória de execução do projeto sheepdog

Atualizada em 2026-10-22 (America/Campo_Grande).

## Estado publicado e decisões preservadas

- Repositório: `diogoprov/sheepdog`; checkout local em
  `/Users/diogoborgesprovete/GitHub/birdnet-validation-sampler`.
- A release `v3.0.0` foi publicada no GitHub, no commit
  `880bc4bb84516ac6c99c94408f1a3895b3824290`:
  https://github.com/diogoprov/sheepdog/releases/tag/v3.0.0.
- O site foi reconstruído e conferido com a versão 3.0.0 e o guia de
  migração: https://provetelab.org/sheepdog/articles/migration-3.0.0.html.
- A transição 2.9.0 foi registrada no commit intermediário `7a7806e`, mas
  não teve release própria. A publicação foi diretamente para a 3.0.0.
- O padrão de `calibrate()` e `select_calibration_model()` é
  `one_se_logloss`; `best_auc` preserva a seleção por AUC da 2.x.
- A leitura dos arquivos da v1.2.0 permanece necessária para a tese da
  Daiene. Os testes de reprodução continuam usando `best_auc` explícito.
- Diogo confirmou que a remoção de `Remotes` no crywolf e a vignette da
  revisão na GUI já estavam concluídas. Não reimplementar essas pendências.
- O CI de cobertura foi configurado com `covr`, artefatos HTML e XML e as
  dependências `DT`/`htmltools`. A publicação do site foi verificada;
  não assumir que todos os checks remotos passaram sem nova consulta.

## Benchmark do Curiango executado

- Fonte: Piatti et al., *Methodological choices influence ecological
  inference in passive acoustic monitoring of a Neotropical nightjar*.
  Dados: https://doi.org/10.5281/zenodo.21795898, versão v2.
- Foram baixadas as tabelas `CM-BirdNet.txt`, `CM-Custom.txt`,
  `df_night_clean.txt` e três scripts para conferir os campos. Os MD5
  foram verificados; o código remoto não foi executado.
- Calibração condicionada a score >= 0,10: 2.939 janelas BirdNET e 8.032
  Custom. A série completa contém 458.520 linhas, 97.806 gravações únicas
  de um minuto e 1.753 combinações local x noite. Há divergência da
  descrição do depósito (97.906 gravações); não alterar a contagem lida
  para reproduzir o número do texto.
- A família padrão m0–m4 só permite estimar m0 com uma espécie; as duas
  regras escolhem o global. Não apresentar o resultado adaptado como uma
  chamada padrão de `calibrate()`.
- Para comparar regras, foi usada uma família adaptada: global, intercepto
  aleatório por local e intercepto/inclinação aleatórios por local.
- Validação aninhada 5 x 5, seed externa 2026, noites inteiras fora do
  treino; sensibilidade por gravação. A regra nova não mostrou vantagem
  consistente. Log-loss BirdNET: 0,458546 (AUC) vs 0,473283 (nova);
  Custom: 0,302171 vs 0,301993. Os intervalos pareados por noite incluem
  zero nos dois classificadores. Não afirmar superioridade universal.
- Com folds por janela e a família adaptada, a mudança altera 14 noites
  no BirdNET e 20 no Custom (nove ganhos e onze perdas no Custom).
  Esses históricos são sensibilidade de presença acústica, não nova
  estimativa de ocupação nem reanálise dos modelos ambientais do artigo.
- Artefatos locais completos (relatório, scripts, dados derivados e modelos):
  `/Users/diogoborgesprovete/Documents/Codex/2026-10-22/como-x20/outputs/curiango-benchmark/`.
  Os dados brutos baixados ficam em `work/curiango/data/` na mesma conversa,
  fora deste repositório.

## Correções posteriores à release, implementadas localmente

A versão de desenvolvimento foi aberta como `3.0.0.9000`; estas mudanças
não foram publicadas em uma nova release nem enviadas ao remoto nesta etapa.

1. `cell_status()` agora inclui o menor e o maior score revisados na
   grade e restringe seus pontos ao intervalo observado. Resolve o
   cruzamento próximo de 1 que a grade de 0,01 perdia e evita arredondar
   o limite inferior para fora do domínio revisado.
2. Nova função exportada `calibration_folds()`: devolve um vetor de folds
   alinhado às linhas da validação. O default mantém a atribuição antiga
   por clipe, dentro de local x espécie, e preserva o estado aleatório.
3. `compare_calibration_models()` e `calibrate()` aceitam `fold_group`,
   por exemplo `"source_audio"` ou `"night"`. Local entra sempre na chave;
   espécies que compartilham um grupo permanecem juntas. Balanceia grupos
   por local; exige pelo menos `k_folds` grupos em cada local e IDs
   completos. Não é uma avaliação em locais novos. Espécies raras podem
   faltar em uma partição. O default continua sem agrupamento.
4. `read_validations(keep = )` retém metadados somente quando solicitado,
   preservando a estrutura antiga por padrão. `calibrate()` solicita os
   campos automaticamente e grava `calibration_folds.csv` para auditoria.
   Campos ausentes provocam erro, sem voltar silenciosamente a folds de
   clipes. Tabelas antigas sem metadados continuam válidas no default.
5. Folds de teste de uma só classe têm AUC ausente, mas contribuem
   log-loss/Brier; não contam como falha de ajuste. Seleção sem AUC ou
   sem log-loss finita produz erro claro.
6. Foram atualizados NEWS, README, documentação roxygen/Rd, referência do
   pkgdown e vignette de calibração, com exemplos das duas formas de uso.

## Verificações desta etapa

- Suíte completa: 362 verificações passaram; zero falhas e zero avisos.
  Um teste Stan foi pulado porque exige `SHEEPDOG_TEST_BRMS=true`.
- `R CMD check` com `--no-manual --ignore-vignettes` e build sem vignettes:
  zero erros, zero warnings, uma NOTE pela consulta de horário pela rede
  indisponível. A checagem não confirma um build completo das vignettes.
- A vignette `calibration.Rmd` foi renderizada separadamente com sucesso.
- Curiango: 56 células conferidas contra os extremos das curvas; as 12
  classificações incorretas anteriores foram corrigidas, com zero
  divergências restantes. Dados em `cell_status_after_fix.csv`.
- A nova API reproduziu a comparação por noites do benchmark manual:
  diferenças máximas de log-loss de 5,55e-17 e de AUC de 1,11e-16.
  Dados em `grouped_folds_api_verification.csv`.
- Testes cobrem limiares próximos de 1, limites inferiores não arredondados
  para fora da faixa, scores constantes, grupos compartilhados entre
  espécies, ausência de vazamento, reprodutibilidade, IDs ausentes,
  grupos insuficientes, metadados opcionais, folds de uma classe e a
  passagem das opções pelo wrapper com arquivo de auditoria.

## Próximos passos pendentes

- Revisar e publicar as correções de desenvolvimento em versão posterior;
  a tag v3.0.0 publicada não contém estas mudanças.
- Conferir os checks remotos e a cobertura antes de uma nova release.
- Ainda não foram implementados candidatos automáticos para uma espécie.
  A família adaptada do benchmark não foi acrescentada a `calibration_models()`.
- Fazer benchmark multiespécies para avaliar a aplicação principal.
- CRAN e artigo de software permanecem decisões do Diogo, conforme o
  [roadmap](roadmap-v3.0.0.md).
