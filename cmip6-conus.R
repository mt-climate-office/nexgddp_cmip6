# install.packages("pak")
packages <- 
  c(
    "magrittr",
    "terra",
    "tidyverse",
    "multidplyr",
    "sf"
  )

pak::pkg_install(packages)

purrr::walk(packages,
            library,
            character.only = TRUE)

source("nexgddp_cmip6.R")

dir.create(
  file.path("conus")
)
usethis::use_git_ignore("conus")

conus <- 
  sf::read_sf("conus_huc2.fgb")

get_cmip6(conus, 
          outdir = file.path("conus"), 
          workers = 10)

test <-
  opendap.catalog::dap(URL = file.path("https://nex-gddp-cmip6.s3-us-west-2.amazonaws.com", cmip6_files$aws[[1]]),
                       AOI = conus)


library(tictoc)
tic()
cmip6_files %$%
  paste0("https://ds.nccs.nasa.gov/thredds/dodsC/AMES/NEX/GDDP-CMIP6/",
         model,"/", 
         scenario, "/",
         run,"/",
         element,"/",
         dataset) %>%
  magrittr::extract2(1) %>%
  opendap.catalog::dap(URL = .,
                       varname = "hurs",
                       AOI = conus,
                       verbose = FALSE) %$%
  hurs %>%
  terra::writeCDF(filename = "test.nc",
                  overwrite = TRUE)
toc()

x <-
  conus %>%
  sf::st_transform(4326) %>%
  st_rotate() %>%
  sf::st_bbox() %>%
  as.list()

tic()
cmip6_files[1,] %$%
  httr::modify_url(
    paste0("https://ds.nccs.nasa.gov/thredds/ncss/grid/AMES/NEX/GDDP-CMIP6/",
           model,"/", 
           scenario, "/",
           run,"/",
           element,"/",
           dataset),
    query = list(
      var = element,
      north = x$ymax,
      west = x$xmin,
      east = x$xmax,
      south = x$ymin,
      disableProjSubset = "on",
      horizStride = 1,
      time_start = paste0(year, "-01-01"),
      time_end = paste0(as.integer(year) + 1, "-01-01"),
      timeStride = 1,
      addLatLon = TRUE
    )) %>%
  get_ncss(out.path = "test_ncss.nc")
toc()

tic()
"https://nex-gddp-cmip6.s3-us-west-2.amazonaws.com/NEX-GDDP-CMIP6/ACCESS-CM2/historical/r1i1p1f1/hurs/hurs_day_ACCESS-CM2_historical_r1i1p1f1_gn_1950.nc" %>%
  terra::rast() %>%
  terra::crop(conus %>%
                sf::st_transform(4326) %>%
                st_rotate(), 
              snap = "out") %>%
  terra::writeCDF(filename = "test.nc",
                  overwrite = TRUE)
toc()
