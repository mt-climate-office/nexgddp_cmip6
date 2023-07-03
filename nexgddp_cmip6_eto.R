## CMIP6
library(magrittr)
devtools::install_github("mt-climate-office/ETo")
library(ETo)
library(terra)

calc_eto <- function(x, outfile){
  if(file.exists(outfile)){
    return(outfile)
  }
  
  # Convert from K to C
  x$tas <- x$tas - 273.15
  x$tasmax <- x$tasmax - 273.15
  x$tasmin <- x$tasmin - 273.15
  x$hurs %<>% terra::clamp(lower = 0, upper = 100)
  
  junk <-
    ETo::calc_etr_spatial(
    tmean = x$tas, 
    srad = x$rsds, 
    rh = x$hurs, 
    ws = x$sfcWind,
    method = "penman", 
    reference = 0.23,
    elev = elev
  ) %>%
    terra::clamp(lower = 0) %>%
    terra::writeCDF(filename = outfile,
                    varname = "eto",
                    longname = "reference evapotranspiration for grass",
                    unit="mm",
                    overwrite = TRUE)
  
  return(outfile)
  
}

# elev <-
#   list.files(file.path(data_raw, "nexgddp_cmip6"),
#              full.names = TRUE,
#              pattern = ".nc$") %>%
#   magrittr::extract2(1) %>%
#   terra::rast() %>%
#   magrittr::extract2(1) %>%
#   {terra::mask(ETo::get_elev_from_raster(., z = 3), .)}
#   
# 
# terra::writeRaster(elev,
#                    filename = "elev_conus.tif",
#                    overwrite = TRUE,
#                    gdal = c("COMPRESS=DEFLATE", "of=COG"),
#                    memfrac = 0.9)

elev <- terra::rast("elev_conus.tif")

library(multidplyr)
cl <- multidplyr::new_cluster(10)
multidplyr::cluster_library(cl, "magrittr")
multidplyr::cluster_copy(cl, "calc_eto")
multidplyr::cluster_send(cl, elev <- terra::rast("elev_conus.tif"))

x <-
  list.files("conus",
             full.names = TRUE,
             pattern = ".nc$") %>%
  tibble::tibble(rast = .) %>%
  dplyr::mutate(dat = 
                  rast %>%
                  basename() %>%
                  tools::file_path_sans_ext()) %>%
  tidyr::separate(dat, into = c("element", "timescale", "model","scenario","run","gn", "year"),
                  sep = "_") %>%
  dplyr::group_by(model, scenario, run, year) %>%
  dplyr::arrange(model, scenario, run, year) %>%
  multidplyr::partition(cl) %>%
  dplyr::summarise(eto = 
    rast %>%
      purrr::map(terra::rast) %>%
      magrittr::set_names(element) %>%
      calc_eto(outfile = paste0(dirname(rast[[1]]),
                                "/",
                                   paste("eto", timescale, model, scenario, run, gn, year,sep = "_")[[1]],
                                ".nc"))
  ) %>%
  dplyr::collect()

rm(cl)
gc()
gc()
