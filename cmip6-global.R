packages <- c("magrittr",
              "terra",
              "tidyverse",
              "multidplyr"
)
purrr::walk(packages, devtools::install_cran)
purrr::walk(packages,
            library,
            character.only = TRUE)

source("nexgddp_cmip6.R")

dir.create(
  file.path("global")
)
usethis::use_git_ignore("global")

get_cmip6_aws(outdir = file.path("global"), workers = 20)
