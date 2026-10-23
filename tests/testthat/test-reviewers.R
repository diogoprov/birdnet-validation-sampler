test_that("assign_reviewers() balances clips and draws the overlap", {
  man <- tibble::tibble(species_code = rep(c("a", "b"), each = 50),
                        species_folder = rep(c("a", "b"), each = 50),
                        clip_file = paste0("c", 1:100, ".wav"))
  m <- assign_reviewers(man, c("ana", "bia", "caio"), overlap = 0.2)
  expect_identical(nrow(m), 100L)
  # equilibrio dentro da especie (50 clipes / 3 revisores)
  n <- dplyr::count(m, species_code, reviewer)$n
  expect_true(all(n %in% 16:17))
  # 20 % de cada especie com segundo revisor, sempre diferente do primeiro
  expect_identical(sum(!is.na(m$second_reviewer)), 20L)
  dupla <- m[!is.na(m$second_reviewer), ]
  expect_true(all(dupla$second_reviewer != dupla$reviewer))
  expect_identical(assign_reviewers(man, c("ana", "bia")),
                   assign_reviewers(man, c("ana", "bia")))
  expect_error(assign_reviewers(man, "ana"), "at least two")
})

test_that("reviewer_agreement() computes Cohen's and Fleiss' kappa", {
  # dois revisores, 10 clipes: concordam em 8
  a <- c(rep("positive", 6), rep("negative", 4))
  b <- c(rep("positive", 5), "negative", "positive", rep("negative", 3))
  rev <- list(
    ana = tibble::tibble(species_folder = "x", clip_file = paste0(1:10),
                         verdict = a),
    bia = tibble::tibble(species_folder = "x", clip_file = paste0(1:10),
                         verdict = b))
  ag <- reviewer_agreement(rev)
  expect_identical(ag$method, "Cohen")
  expect_equal(ag$agreement, 0.8)
  # kappa de Cohen a mao: p_o = 0.8; p_e = 0.6*0.6 + 0.4*0.4 = 0.52
  expect_equal(ag$kappa, (0.8 - 0.52) / (1 - 0.52))
  # tres revisores: Fleiss
  rev$caio <- tibble::tibble(species_folder = "x", clip_file = paste0(1:10),
                             verdict = a)
  ag3 <- reviewer_agreement(rev)
  expect_identical(ag3$method, "Fleiss")
  expect_true(ag3$kappa > 0 && ag3$kappa < 1)
  # concordancia perfeita
  rev2 <- list(ana = rev$ana, bia = rev$ana)
  expect_equal(reviewer_agreement(rev2)$kappa, 1)
})

test_that("consensus_verdicts() marks conflicting clips", {
  rev <- list(
    ana = tibble::tibble(species_folder = "x", clip_file = c("1", "2", "3"),
                         verdict = c("positive", "negative", "positive")),
    bia = tibble::tibble(species_folder = "x", clip_file = c("1", "2"),
                         verdict = c("positive", "positive")))
  cons <- suppressMessages(consensus_verdicts(rev))
  expect_identical(nrow(cons), 3L)
  v <- setNames(cons$verdict, cons$clip_file)
  expect_identical(unname(v[c("1", "2", "3")]),
                   c("positive", "disagreement", "positive"))
  expect_identical(cons$n_reviewers[cons$clip_file == "3"], 1L)
  expect_message(consensus_verdicts(rev), "conflicting")
})

test_that("split_by_reviewer() copies clips to each reviewer", {
  d <- withr::local_tempdir()
  man <- tibble::tibble(species_code = "a", species_folder = "a",
                        clip_file = paste0("c", 1:10, ".wav"))
  dir.create(file.path(d, "clips", "a"), recursive = TRUE)
  file.create(file.path(d, "clips", "a", man$clip_file))
  m <- assign_reviewers(man, c("ana", "bia"), overlap = 0.2)
  out <- suppressMessages(split_by_reviewer(m, file.path(d, "clips"),
                                            file.path(d, "rev")))
  expect_identical(nrow(out), 12L)
  n_ana <- length(list.files(file.path(d, "rev", "ana", "a")))
  n_bia <- length(list.files(file.path(d, "rev", "bia", "a")))
  expect_identical(n_ana + n_bia, 12L)
})

test_that("reviewer agreement handles absent overlap and undefined kappa", {
  one <- tibble::tibble(species_folder = "sp", clip_file = c("1", "2"),
                        verdict = "positive", reviewer = "ana")
  expect_warning(empty <- reviewer_agreement(one), "No clip")
  expect_equal(nrow(empty), 0L)
  # Perfect agreement with no variation has undefined chance correction.
  both <- dplyr::bind_rows(one, dplyr::mutate(one, reviewer = "bia"))
  out <- reviewer_agreement(both)
  expect_equal(out$agreement, 1)
  expect_true(is.na(out$kappa))
  three <- dplyr::bind_rows(both, dplyr::mutate(one, reviewer = "caio"))
  expect_true(is.na(reviewer_agreement(three)$kappa))
  expect_error(reviewer_agreement(one[c("species_folder", "clip_file", "verdict")]),
                "reviewer.*column")
  expect_error(reviewer_agreement(list(one, one)), "named by reviewer")
  expect_error(assign_reviewers(one, c("ana", "ana")), "unique")
  expect_error(assign_reviewers(one, c("ana", "bia"), overlap = 2), "between 0 and 1")
})
