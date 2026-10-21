test_that("simulate_pam escreve tabelas Raven e audios vazios", {
  raiz <- withr::local_tempdir()
  pred <- simulate_pam(raiz)
  tabs <- list.files(raiz, "^BirdNET_SelectionTable\\.txt$", recursive = TRUE)
  expect_length(tabs, 3)
  cols <- names(utils::read.delim(file.path(raiz, tabs[1]), check.names = FALSE))
  expect_true(all(c("Begin Time (s)", "End Time (s)", "Species Code",
                    "Confidence", "Begin Path", "File Offset (s)") %in% cols))
  wavs <- list.files(file.path(raiz, "audio"), "\\.wav$", recursive = TRUE)
  expect_true(all(grepl("_\\d{8}_\\d{6}\\.wav$", wavs)))
  expect_true(all(file.size(file.path(raiz, "audio", wavs)) == 0))
})
