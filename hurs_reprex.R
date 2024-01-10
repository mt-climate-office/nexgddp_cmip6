reprex::reprex({
  library(magrittr)
  library(terra)
  library(httr)
  
  # NASA NEX-GDDP-CMIP6
  nexgddp <- tempfile(fileext = ".nc")
  "https://nex-gddp-cmip6.s3-us-west-2.amazonaws.com/NEX-GDDP-CMIP6/ACCESS-ESM1-5/historical/r1i1p1f1/hurs/hurs_day_ACCESS-ESM1-5_historical_r1i1p1f1_gn_2000_v1.1.nc"  %>%
    httr2::request() %>%
    httr2::req_perform(path = nexgddp,
                       verbosity = 0)
  # Values outside of [0,100]
  (terra::rast(nexgddp)[[1]] > 100) %>%
    plot()
    
  
  # Original CMIP6 Model (warning, ~490 MB)
  cmip6 <- tempfile(fileext = ".nc")
  "https://esgf-data1.llnl.gov/thredds/fileServer/css03_data/CMIP6/CMIP/CSIRO/ACCESS-ESM1-5/historical/r1i1p1f1/day/hurs/gn/v20191115/hurs_day_ACCESS-ESM1-5_historical_r1i1p1f1_gn_20000101-20141231.nc" %>%
    httr2::request() %>%
    httr2::req_perform(path = cmip6,
                       verbosity = 0)
  # Values outside of [0,100]
  terra::rast(cmip6)[[1]] %>%
    plot()
  
})