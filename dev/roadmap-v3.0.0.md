# Roadmap: sheepdog 3.0.0

Estado de partida: `main` em `3a6b5e1` (sheepdog 2.0.0 + PRs #12–#18, ainda
sem release). Este roadmap junta o que ficou pendente na conversão para
pacote e o que as vignettes revelaram sobre a API. Itens marcados
**[decidir]** dependem de uma escolha do Diogo antes de implementar.

A v3.0.0 é major porque muda o comportamento padrão da seleção do modelo
de calibração. Todo o resto pode entrar antes, em versões 2.x.

Decisões tomadas (2026-10-22): a leitura dos arquivos da v1.2.0 fica
(memória do projeto; a tese da Daiene ainda usa esses arquivos); entram o
backend com `brms`, as medidas de calibração, o critério de células para as
espécies-núcleo e o suporte a vários revisores, como descritos abaixo.

## 0. Antes da v3: fechar a 2.1.0

Itens prontos ou quase, que não quebram nada. Sugestão: release 2.1.0 logo,
para o DOI do Zenodo acompanhar as vignettes novas.

- [x] **README: instalação pelo r-universe.** Esperar o r-universe compilar a
  `main` sem ERROR no Linux e no Windows (o build atual ainda é do
  `bca52ed`, anterior à correção do #14). Depois: `install.packages("sheepdog",
  repos = c("https://diogoprov.r-universe.dev", "https://cloud.r-project.org"))`
  como instalação principal, `remotes::install_github()` como alternativa,
  e badge do r-universe. *(Feito: 2.1.0, PR #21.)*
- [ ] **crywolf:** trocar `Remotes: diogoprov/sheepdog` por
  `https://diogoprov.r-universe.dev` em `Additional_repositories` (formato
  aceito pelo CRAN para Suggests fora dele). PR no repositório do crywolf.
- [x] **NEWS:** fechar a seção "development version" como 2.1.0; atualizar
  `CITATION.cff` (versão, data); release no GitHub (gera o DOI da versão). *(Feito: 2.1.0, PR #22.)*

## 1. Mudanças que quebram compatibilidade (definem a 3.0.0)

- [ ] **Seleção do modelo de calibração em `calibrate()`** (decidido; a regra já existe desde a 2.2.0, PR #23, como `select = "one_se_logloss"`; falta torná-la o padrão na 3.0.0).
  Hoje: maior AUC médio (`cv$model[1]`), mesmo que o ajuste seja singular e
  que a diferença para um modelo mais simples seja menor que `auc_sd`. O
  AUC mede discriminação, mas o que vai para o histórico é a probabilidade
  comparada com `p_min`. Novo padrão:
  1. escolher pela **log-loss** nos folds (regra de pontuação própria;
     Gneiting & Raftery 2007, doi:10.1198/016214506000001437);
  2. regra de 1 erro-padrão: entre os modelos a até 1 EP da melhor
     log-loss, o mais simples (m0 < m1 < ... < m4);
  3. excluir ajustes singulares, a menos que todos sejam (aí, avisar);
  4. `select = c("one_se_logloss", "best_auc")`; `"best_auc"` reproduz a
     2.x. A tabela de comparação reporta todas as métricas.
  Na 2.9.x, avisar que o padrão vai mudar.
- [x] ~~Remover a leitura dos arquivos da v1.2.0~~: **fica** (decidido). Os
  testes de reprodução da v1.2.0 também ficam.

## 2. Calibração

- [x] **Variante sem correlação do m4** em `calibration_models()`
  (`(1 | species) + (0 + logit_conf | species) + (1 | site:species)`). No
  exemplo, o m4 é singular só pela correlação intercepto–inclinação de
  espécie (+1); a variante resolveria isso sem perder o efeito local ×
  espécie. *(Feito: 2.2.0, PR #23.)*
- [x] **Backend bayesiano opcional com `brms`** (decidido): `engine =
  c("lme4", "brms")`, mesma família m0–m4; argumento `prior` obrigatório com
  `engine = "brms"` (a documentação traz um exemplo fracamente informativo
  na escala logito); saída com R-hat, ESS e divergências, com aviso quando
  passarem dos limites; posterior predictive check (ex.: proporção de TP
  por faixa de score); P(TP) de cada detecção como posterior, permitindo
  regras do tipo P(P(TP) >= `p_min`) alta. `brms` em Suggests. *(Feito: 2.2.0, PR #28.)*
- [ ] **Mensagens do `glmer()`** *(adiado para a 2.3.0)*: hoje `fit_model()` usa `suppressMessages()`;
  a singularidade já vira aviso (2.x), mas outras mensagens informativas
  somem. Repassar as mensagens ao usuário, ou registrá-las no objeto.
- [x] **Medidas de calibração além do AUC** (decidido), todas nos folds de
  teste: log-loss (seleção), Brier score (relato), intercepto e inclinação
  de calibração (diagnóstico: ideal 0 e 1) e gráfico de confiabilidade. Não
  usar ECE (depende das faixas). Referência para as medidas: Van Calster et
  al. (2019) *BMC Medicine* 17, doi:10.1186/s12916-019-1466-7 (conferir o
  número do artigo antes de citar). *(Feito: 2.2.0, PR #23.)*

## 3. Amostragem (`select_clips()`)

- [x] **Estrato do sorteio em `random_detections`**: com uma gravação por
  hora, o sorteio por arquivo dentro de local × espécie × noite × hora não
  sorteia nada (`inclusion_prob` = 1; visto na vignette de desenhos
  amostrais). Argumento `strata` para escolher estratos mais grossos (ex.:
  sem hora, ou só local × espécie). *(Feito: 2.2.0, PR #24.)*
- [x] ~~**Pesos de desenho**: devolver também `design_weight = 1 /
  inclusion_prob` e documentar como estimar a precisão agregada entre
  espécies com pesos.~~ *(Descartado na 2.2.0: seria só `1 / inclusion_prob` e mudaria o formato do manifesto; a documentação de `select_clips()` explica a ponderação.)*
- [x] **Mensagem "0 predictions dropped"**: não emitir quando nada é
  descartado (cosmético). *(Feito: 2.2.0, PR #24.)*
- [x] **Manifesto com proveniência**: colunas ou atributos com a versão do
  classificador e do BirdNET-Analyzer, data da extração e versão do
  sheepdog. Necessário para o item de retreino abaixo. *(Feito: 2.2.0, PR #24: arquivo `extraction_info.csv`, não colunas, para não mudar o formato que o crywolf lê.)*

## 4. Pós-validação e retreino

- [x] **`build_training_set()`**: transformar a função `copy_to_training()`
  da vignette de retreino em função exportada (positivos em
  `<species_code>/`, negativos em `-<species_code>/`, separação de teste por
  local ou noite, contagem contra o mínimo recomendado). *(Feito: 2.2.0, PR #25.)*
- [x] **Excluir clipes usados no treino** de rodadas de validação
  posteriores (depende da proveniência no manifesto). *(Feito: 2.2.0, PR #25: `exclude_training_clips()`.)*
- [x] **Vários revisores** (decidido): `assign_reviewers()` divide os
  pacotes com uma fração sobreposta (ex.: 10 %) estratificada por espécie;
  concordância por espécie com kappa de Cohen (dois revisores; Cohen 1960,
  doi:10.1177/001316446002000104) ou de Fleiss (mais de dois; Fleiss 1971,
  doi:10.1037/h0031619); discordâncias vão para uma lista de consenso; o
  manifesto guarda o revisor de cada clipe; com concordância baixa, a
  calibração pode incluir o revisor como efeito aleatório. *(Feito: 2.2.0, PR #27.)*
- [x] **Leitura das tabelas de validação "cruas"**: helper que empilha os
  `validation_by_clip.csv` mantendo `species_folder` e `verdict` (hoje as
  vignettes fazem isso à mão; `read_validations()` devolve só o formato da
  calibração). *(Feito: 2.2.0, PR #25: `read_validation_tables()`.)*

## 5. Matrizes de comunidade

- [x] **Espécies-núcleo por estado das células** (decidido): `cell_status()`
  classifica cada local x espécie em
  * *confiável*: a curva calibrada atinge `p_min` dentro da faixa de scores
    observada e há >= `min_n` clipes revisados;
  * *provavelmente ausente*: poucas detecções e nenhum TP revisado (entra
    como zero);
  * *não confiável*: há TP revisados, mas a curva não atinge `p_min`, ou há
    clipes de menos (não pode entrar como zero).
  Espécies-núcleo = sem células não confiáveis. Alternativa: matrizes com
  `NA` nas células não confiáveis (o GLLVM aceita; a PCoA não). A escolha
  final continua com o usuário. *(Feito: 2.2.0, PR #26.)*
- [x] **Linhas só com zeros**: `community_matrices()` pode devolver amostras
  sem nenhuma detecção das espécies-núcleo; documentar ou oferecer
  `drop_empty = TRUE`. *(Feito: 2.2.0, PR #26: `drop_empty`.)*
- [x] **Saída pronta para o gllvm**: devolver também a matriz de tentativas
  (`Ntrials` com as dimensões da resposta), que o `gllvm` exige como matriz. *(Feito: 2.2.0, PR #26: `trials`.)*

## 6. Documentação

- [ ] **Vignette da revisão na GUI do BirdNET**, com as capturas de tela da
  Liliana (pedido enviado). Link para a documentação oficial da GUI.
- [x] **README**: listar `summarise_history()` e as funções novas; revisar a
  tabela de funções após a 3.0.0. *(Feito: 2.2.0.)*
- [ ] **Guia de migração 2.x → 3.0.0** (critério de seleção do modelo).

## 7. Infraestrutura

- [x] **r-universe verde** em todas as plataformas (depende do build da
  `main` atual). *(Feito: 2.1.0.)*
- [ ] **Cobertura de testes** (`covr`) no CI.
- [ ] **CRAN** **[decidir]**: viável depois da 3.0.0. Pontos a resolver: o
  crywolf em Suggests fora do CRAN (aceito com `Additional_repositories`),
  tempo das vignettes (lme4, gllvm) e tamanho de `inst/extdata` (1,7 MB).
- [ ] **Artigo de software** **[decidir]** (ex.: *Methods in Ecology and
  Evolution* Applications ou JOSS), junto com o crywolf ou separado.

## Ordem sugerida

1. 2.1.0: README/r-universe, crywolf `Additional_repositories`, release.
2. 2.2.0: itens não quebradores de calibração (variante sem correlação,
   mensagens, medida de calibração), amostragem (estratos, pesos,
   proveniência), `build_training_set()`, helpers das matrizes, vignette da
   GUI.
3. 2.9.x: aviso de que o critério padrão de seleção vai mudar.
4. 3.0.0: novo padrão de seleção (log-loss + 1 EP, sem singulares) e guia
   de migração; `brms` e vários revisores, se não tiverem entrado antes;
   avaliar CRAN e artigo.
