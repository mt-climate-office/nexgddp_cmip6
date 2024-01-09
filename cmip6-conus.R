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
  file.path("conus_s3")
)
usethis::use_git_ignore("conus_s3")

# https://prd-tnm.s3.amazonaws.com/StagedProducts/Hydrography/WBD/National/GDB/WBD_National_GDB.zip
# conus <- sf::read_sf("~/Downloads/WBD_National_GDB/WBD_National_GDB.gdb/", "WBDHU2") %>%
#   dplyr::filter(huc2 %in% stringr::str_pad(1:18, width = 2, pad = "0")) %>%
#   sf::st_transform(5070) %>%
#   sf::st_make_valid() %>%
#   dplyr::select(huc2, name) %>%
#   dplyr::summarise() %>%
#   sf::st_buffer(50000) %>%
#   sf::write_sf("conus_huc2.fgb")

# sf::read_sf("wbdhu2_a_us_september2021.gdb/", "WBDHU2") %>%
#   dplyr::filter(huc2 %in% stringr::str_pad(10:18, width = 2, pad = "0")) %>%
#   sf::st_transform(5070) %>%
#   sf::st_make_valid() %>%
#   dplyr::select(huc2, name) %>%
#     sf::write_sf("conus_huc2_real.fgb")

conus <- 
  sf::read_sf("conus_huc2.fgb") %>%
  sf::st_transform(4326) %>%
  st_rotate()

get_cmip6_s3(x = conus, 
             s3_mount = "/private/tmp/cmip6", 
             outdir = file.path("conus_s3"), 
             workers = 20)

get_cmip6(conus, outdir = file.path("conus"), workers = 20)

library(terra)
cmip6_files

test <- 
  terra::rast("/private/tmp/cmip6/NEX-GDDP-CMIP6/ACCESS-ESM1-5/ssp126/r1i1p1f1/tas/tas_day_ACCESS-ESM1-5_ssp126_r1i1p1f1_gn_2015_v1.1.nc") %>%
  terra::crop(x,
              snap = "out",
              mask = TRUE,
              filename = "paleocar_v3/ppt_water_year/cube_v3.zarr",
              overwrite = TRUE,
              gdal = c("FORMAT=ZARR_V3"),
              filetype = "Zarr",
              NAflag = NA
              )
  
