test_that("read_selection_tables() names sites by folder", {
  pred <- suppressMessages(
    read_selection_tables(file.path(sim_root(), "tabelas")))
  expect_identical(names(pred)[1], "site")
  expect_setequal(unique(pred$site), c("ARA", "XAR", "BAI"))
  expect_true(all(c("begin_time", "end_time", "species_code", "confidence",
                    "begin_path", "file_offset") %in% names(pred)))
})

test_that("read_selection_tables() reports missing columns", {
  d <- withr::local_tempdir()
  dir.create(file.path(d, "SITE"))
  writeLines("Begin Time (s)\tConfidence\n0\t0.5",
             file.path(d, "SITE", "BirdNET_SelectionTable.txt"))
  expect_error(suppressMessages(read_selection_tables(d)), "lacks the columns")
})

test_that("read_selection_tables() fails when nothing is found", {
  expect_error(read_selection_tables(withr::local_tempdir()),
               "No selection table")
})
