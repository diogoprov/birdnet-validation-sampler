# Roadmap: sheepdog 3.0.0

Estado de partida: `main` em `3a6b5e1` (sheepdog 2.0.0 + PRs #12–#18, ainda
sem release). Este roadmap junta o que ficou pendente na conversão para
pacote e o que as vignettes revelaram sobre a API. Itens marcados
**[decidir]** dependem de uma escolha do Diogo antes de implementar.

A v3.0.0 é major porque muda comportamento padrão (seleção do modelo de
calibração) e remove a leitura dos arquivos da v1.2.0. Todo o resto pode
entrar antes, em versões 2.x.

## 0. Antes da v3: fechar a 2.1.0

Itens prontos ou quase, que não quebram nada. Sugestão: release 2.1.0 logo,
para o DOI do Zenodo acompanhar as vignettes novas.

- [ ] **README: instalação pelo r-universe.** Esperar o r-universe compilar a
  `main` sem ERROR no Linux e no Windows (o build atual ainda é do
  `bca52ed`, anterior à correção do #14). Depois: `install.packages("sheepdog",
  repos = c("https://diogoprov.r-universe.dev", "https://cloud.r-project.org"))`
  como instalação principal, `remotes::install_github()` como alternativa,
  e badge do r-universe.
- [ ] **crywolf:** trocar `Remotes: diogoprov/sheepdog` por
  `https://diogoprov.r-universe.dev` em `Additional_repositories` (formato
  aceito pelo CRAN para Suggests fora dele). PR no repositório do crywolf.
- [ ] **NEWS:** fechar a seção "development version" como 2.1.0; atualizar
  `CITATION.cff` (versão, data); release no GitHub (gera o DOI da versão).

## 1. Mudanças que quebram compatibilidade (definem a 3.0.0)

- [ ] **Seleção do modelo de calibração em `calibrate()`** **[decidir]**.
  Hoje: maior AUC médio (`cv$model[1]`), mesmo que o ajuste seja singular e
  que a diferença para um modelo mais simples seja menor que `auc_sd`. A
  vignette de calibração mostrou que a escolha muda com `k_folds` quando os
  AUCs empatam. Proposta: argumento `select = c("one_se", "best_auc")`, com
  padrão `"one_se"` (o modelo mais simples dentro de 1 DP do melhor) e
  preferência por modelos não singulares; `"best_auc"` reproduz a 2.x.
- [ ] **Remover a leitura dos arquivos da v1.2.0** (`R/legacy.R`, colunas e
  valores em português) **[decidir]**. Caminho: na 2.x, avisar com
  `lifecycle::deprecate_warn()` ao ler um arquivo antigo; na 3.0.0, remover,
  mantendo um script em `data-raw/` ou uma função `convert_v1()` para quem
  ainda tiver validações antigas (FrogNet, tese da Daiene).
- [ ] **Testes de reprodução da v1.2.0**: saem junto com a leitura antiga;
  as saídas de referência viram snapshot da própria 3.0.0.

## 2. Calibração

- [ ] **Variante sem correlação do m4** em `calibration_models()`
  (`(1 | species) + (0 + logit_conf | species) + (1 | site:species)`). No
  exemplo, o m4 é singular só pela correlação intercepto–inclinação de
  espécie (+1); a variante resolveria isso sem perder o efeito local ×
  espécie.
- [ ] **Backend bayesiano opcional com `brms`** **[decidir]**: mesma família
  de modelos, com priors declarados explicitamente (argumento obrigatório,
  sem defaults implícitos), saída com R-hat, ESS, divergências e posterior
  predictive check. Útil quando o GLMM é singular ou há poucas células. Seria
  Suggests; custo: tempo de ajuste e dependência do Stan.
- [ ] **Mensagens do `glmer()`**: hoje `fit_model()` usa `suppressMessages()`;
  a singularidade já vira aviso (2.x), mas outras mensagens informativas
  somem. Repassar as mensagens ao usuário, ou registrá-las no objeto.
- [ ] **Calibração de curvas em vez de só AUC**: o AUC mede discriminação,
  não calibração. Acrescentar à comparação de modelos uma medida de
  calibração (ex.: Brier score ou log-loss nos folds) **[decidir quais]**.

## 3. Amostragem (`select_clips()`)

- [ ] **Estrato do sorteio em `random_detections`**: com uma gravação por
  hora, o sorteio por arquivo dentro de local × espécie × noite × hora não
  sorteia nada (`inclusion_prob` = 1; visto na vignette de desenhos
  amostrais). Argumento `strata` para escolher estratos mais grossos (ex.:
  sem hora, ou só local × espécie).
- [ ] **Pesos de desenho**: devolver também `design_weight = 1 /
  inclusion_prob` e documentar como estimar a precisão agregada entre
  espécies com pesos.
- [ ] **Mensagem "0 predictions dropped"**: não emitir quando nada é
  descartado (cosmético).
- [ ] **Manifesto com proveniência**: colunas ou atributos com a versão do
  classificador e do BirdNET-Analyzer, data da extração e versão do
  sheepdog. Necessário para o item de retreino abaixo.

## 4. Pós-validação e retreino

- [ ] **`build_training_set()`**: transformar a função `copy_to_training()`
  da vignette de retreino em função exportada (positivos em
  `<species_code>/`, negativos em `-<species_code>/`, separação de teste por
  local ou noite, contagem contra o mínimo recomendado).
- [ ] **Excluir clipes usados no treino** de rodadas de validação
  posteriores (depende da proveniência no manifesto).
- [ ] **Vários revisores**: dividir os pacotes entre revisores e, quando um
  subconjunto for revisado por dois, medir a concordância (kappa) **[decidir
  se entra]**.
- [ ] **Leitura das tabelas de validação "cruas"**: helper que empilha os
  `validation_by_clip.csv` mantendo `species_folder` e `verdict` (hoje as
  vignettes fazem isso à mão; `read_validations()` devolve só o formato da
  calibração).

## 5. Matrizes de comunidade

- [ ] **Escolha das espécies-núcleo**: helper que sugere as espécies a
  partir dos diagnósticos da calibração (ex.: P(TP) ≥ `p_min` atingível em
  todos os locais) em vez de o usuário escolher à mão. A vignette usa
  "confiável em todos os locais" como aproximação, que não separa ausência de
  falha de calibração **[decidir o critério]**.
- [ ] **Linhas só com zeros**: `community_matrices()` pode devolver amostras
  sem nenhuma detecção das espécies-núcleo; documentar ou oferecer
  `drop_empty = TRUE`.
- [ ] **Saída pronta para o gllvm**: devolver também a matriz de tentativas
  (`Ntrials` com as dimensões da resposta), que o `gllvm` exige como matriz.

## 6. Documentação

- [ ] **Vignette da revisão na GUI do BirdNET**, com as capturas de tela da
  Liliana (pedido enviado). Link para a documentação oficial da GUI.
- [ ] **README**: listar `summarise_history()` e as funções novas; revisar a
  tabela de funções após a 3.0.0.
- [ ] **Guia de migração 2.x → 3.0.0** (seleção do modelo, leitura legada).

## 7. Infraestrutura

- [ ] **r-universe verde** em todas as plataformas (depende do build da
  `main` atual).
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
3. 2.9.x: avisos de depreciação da leitura v1.2.0 e do critério de seleção.
4. 3.0.0: novo padrão de seleção, remoção da leitura legada, guia de
   migração; avaliar CRAN e artigo.
