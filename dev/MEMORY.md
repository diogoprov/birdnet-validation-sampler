# Memória de execução do projeto sheepdog

Atualizada em 2026-10-22 (America/Campo_Grande).

## Publicação 3.1.0

- As correções de `cell_status()` e os folds agrupados foram enviadas à
  main e publicadas na release 3.1.0, após autorização do Diogo.
- Tag `v3.1.0`, commit `847a5b38825b58ec64d96545ea74bbd9a1a6a799`;
  release pública, definitiva e marcada como latest (não prerelease).
- Release: https://github.com/diogoprov/sheepdog/releases/tag/v3.1.0.
- DESCRIPTION, NEWS e CITATION.cff foram atualizados para 3.1.0.
- A cobertura da 3.0.0 foi confirmada como concluída com sucesso; o
  R-CMD-check remoto ainda aparecia em execução na consulta desta etapa.
- Para a 3.1.0, a evidência local permanece: 362 verificações passaram,
  check com zero erros/avisos e uma nota de horário, vignette renderizada,
  12 células corrigidas e reprodução dos folds manuais do Curiango.
- Os resultados remotos da nova versão devem ser consultados no GitHub;
  não confundir o sucesso local com o sucesso de todos os jobs remotos.

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

A implementação começou em `3.0.0.9000` (commit `20e6d33`) e foi
preparada para a release 3.1.0 na etapa de publicação seguinte.

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

## Candidatos para uma espécie e vignette de desempenho (após 3.1.0)

- Diogo confirmou que não há conjunto real multiespécies disponível.
  O benchmark multiespécies desta etapa é explicitamente uma simulação,
  não validação empírica do FrogNet.
- Implementado `calibration_models(single_species = TRUE)`: global,
  intercepto de local, intercepto/inclinação de local e opção sem
  correlação. A seleção automática de `calibrate()` e
  `compare_calibration_models(models = NULL)` usa os níveis observados.
  Uma espécie em um local usa só m0; várias espécies em um local omitem
  os efeitos de local não estimáveis. A família multiespécies original e
  sua ordem permanecem, e listas explícitas sobrescrevem a escolha da
  comparação. A implementação começou em `3.1.0.9000`.
- Conferida a nova família automática no Curiango: três candidatos e zero
  ajustes de fold falhos para cada classificador; métricas coincidem com
  a família explícita do relatório a menos de 1e-15. Três repetições
  mediram o tempo de cada comparação de cinco folds.
- Executadas 60 simulações independentes (três cenários x 20 seeds,
  2026–2045), seis locais, oito espécies, 24 noites de treino e 12 de
  teste, duas janelas por célula-noite. Seleção em cinco folds de noites
  do treino; noites de teste nunca entram na seleção ou no reajuste.
  Resultados: 1.500 ajustes CV sem falhas, 120 desfechos finais por regra.
- Cenário global: a nova regra escolheu m0 em 20/20 casos, AUC em 13/20;
  log-loss média 0,462734 vs 0,462874 (nova vs AUC). Com diferenças entre
  espécies, 0,460964 vs 0,457612; com local x espécie, 0,446650 vs
  0,444250. Não há ganho consistente universal. Matriz MAE foi comparada
  nos mesmos oito eixos; conjuntos núcleo foram avaliados separadamente.
- Criada `vignettes/performance.Rmd`, no estilo do artigo de desempenho
  do crywolf. Resume o relatório empírico anterior, intervalos e mudanças
  de noites, regressões de células, nova família, simulações, tempos,
  limitações e reprodução. Build não baixa dados nem ajusta modelos.
- Scripts opt-in: `dev/benchmarks/curiango.R`, `curiango-native.R`,
  `multispecies.R` e `check-results.R`. Caches pequenos e metadados de
  proveniência ficam em `inst/benchmarks/` e são distribuídos com o pacote.
- Testes locais desta etapa: 380 verificações passaram, zero falhas e
  avisos; um teste Stan exige ativação e foi pulado. As seleções e perdas
  pareadas dos caches foram conferidas independentemente; persistem as
  12 regressões corrigidas de `cell_status()`.
- `R CMD check` desta etapa (sem manual/compilação de vignettes):
  zero erros, zero avisos e zero notas. A nova vignette foi renderizada
  separadamente sem acesso a dados remotos. A página `performance` também
  foi construída localmente com pkgdown.
- HTML local da nova vignette:
  `/Users/diogoborgesprovete/Documents/Codex/2026-10-22/como-x20/outputs/sheepdog-performance.html`.
- Estas mudanças são posteriores à tag 3.1.0; uma nova publicação ainda
  precisa incluir este desenvolvimento. Não confundir o HTML local com
  um deploy já concluído do site público.

## Próximos passos pendentes

- Conferir checks, cobertura e deploy do site da 3.1.0; a tag v3.0.0
  não contém as correções posteriores.
- Conferir a distribuição no r-universe e o registro da versão no Zenodo;
  a release GitHub foi confirmada, mas esses serviços não foram validados.
- Conferir os checks remotos e a cobertura antes de uma nova release.
- Candidatos automáticos e benchmark multiespécies simulado foram concluídos
  nesta etapa; benchmark empírico multiespécies continua dependendo de dados
  reais, que não estão disponíveis.
- Revisar e publicar a nova API e a vignette de desempenho em versão futura.
- CRAN e artigo de software permanecem decisões do Diogo, conforme o
  [roadmap](roadmap-v3.0.0.md).

## Preparação da release 3.2.0

- Diogo autorizou push e release para a seleção automática de uma espécie
  e a vignette `performance`. Metadados preparados para 3.2.0.
- Checks remotos da main anterior `dd46a93` confirmados: R-CMD-check,
  cobertura e pkgdown concluídos com sucesso.
- Testes do desenvolvimento: 380 verificações, um teste Stan opt-in pulado;
  R CMD check sem erros, avisos ou notas. Benchmarks e artigo renderizados
  na etapa anterior; esta preparação altera metadados e redação de versão.
- URL prevista: https://github.com/diogoprov/sheepdog/releases/tag/v3.2.0.
