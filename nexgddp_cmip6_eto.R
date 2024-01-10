# install.packages("pak")
packages <- 
  c(
    "mt-climate-office/ETo",
    "furrr"
  )

pak::pkg_install(packages)

library(magrittr)
library(ETo)
library(terra)

# elev <-
#   list.files("conus",
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
#                    gdal = c("COMPRESS=DEFLATE"),
#                    memfrac = 0.9)

elev <- terra::rast("elev_conus.tif")

calc_eto <-
  function(x, outfile, force = FALSE){
    if(!force && file.exists(outfile)){
      return(outfile)
    }
    
    ETo::calc_etr_spatial(
      # Convert from K to C
      t_min = x$tasmin - 273.15, 
      t_max = x$tasmax - 273.15,
      srad = x$rsds, 
      # Relative humidity sometimes > 100 in NASA-NEXGDDP
      rh = terra::clamp(x$hurs, lower = 0, upper = 100), 
      ws = x$sfcWind,
      wind_height = 10,
      method = "penman", 
      reference = 0.23,
      elev = elev
    ) %>%
      terra::clamp(lower = 0) %>%
      terra::writeCDF(filename = outfile,
                      varname = "eto",
                      longname = "reference evapotranspiration for grass",
                      unit = "mm",
                      overwrite = TRUE)
    
    return(outfile)
    
  }

### TEST
test <-
  list.files("conus",
           full.names = TRUE,
           pattern = ".nc$") %>%
  tibble::tibble(rast = .) %>%
  dplyr::mutate(dat = 
                  rast %>%
                  basename() %>%
                  tools::file_path_sans_ext()) %>%
  # tidyr::separate(dat, into = c("element", "timescale", "model","scenario","run","gn", "year", "version"),
  #                 sep = "_") %>%
  tidyr::separate_wider_delim(dat, 
                              names = c("element", "timestep", "model", "scenario", "run", "type", "year", "version"), 
                              delim = "_",
                              cols_remove = FALSE,
                              too_few = "align_start") %>%
  dplyr::filter(model == "ACCESS-ESM1-5",
                scenario == "historical",
                year == 1950) %>%
  dplyr::group_by(model, scenario, run, year) %>%
  dplyr::arrange(model, scenario, run, year) %>%
  dplyr::summarise(eto = 
                     rast %>%
                     purrr::map(terra::rast) %>%
                     magrittr::set_names(element) %>%
                     calc_eto(outfile = paste0(dirname(rast[[1]]),
                                               "/",
                                               paste("eto", timestep, model, scenario, run, type, year, "v1.1", sep = "_")[[1]],
                                               ".nc"),
                              force = TRUE)) %$%
  terra::rast(eto)

plot(test[[90]], range = c(0,20))




library(multidplyr)
cl <- multidplyr::new_cluster(min(50, future::availableCores() - 1))
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
  # tidyr::separate(dat, into = c("element", "timescale", "model","scenario","run","gn", "year", "version"),
  #                 sep = "_") %>%
  tidyr::separate_wider_delim(dat, 
                              names = c("element", "timestep", "model", "scenario", "run", "type", "year", "version"), 
                              delim = "_",
                              cols_remove = FALSE,
                              too_few = "align_start") %>%
  # dplyr::filter(model == "ACCESS-ESM1-5",
  #               scenario == "historical",
  #               year == 1950) %>%
  dplyr::group_by(model, scenario, run, year) %>%
  dplyr::arrange(model, scenario, run, year) %>%
  multidplyr::partition(cl) %>%
  dplyr::summarise(eto = 
                     rast %>%
                     purrr::map(terra::rast) %>%
                     magrittr::set_names(element) %>%
                     calc_eto(outfile = paste0(dirname(rast[[1]]),
                                               "/",
                                               paste("eto", timestep, model, scenario, run, type, year, "v1.1", sep = "_")[[1]],
                                               ".nc"))
  ) %>%
  dplyr::collect()

rm(cl)
gc()
gc()
