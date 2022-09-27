library(magrittr)
library(multidplyr)
if (!require(ETo)) devtools::install_github("mt-climate-office/ETo")

f_list <- file.path(Sys.getenv("CMIP6_DIR"), "/nexgddp_cmip6/") %>%
  list.files(full.names = T, include.dirs = FALSE) %>%
  grep(".json", ., value = TRUE, invert = TRUE)

v_list = c("hurs", "rsds", "sfcWind", "tas", "tasmax", "tasmin")

calc_eto_from_group <- function(dat) {
  rh <-
    dplyr::filter(dat, variable == 'hurs') %$% terra::rast(f_list) %>%
    terra::clamp(0, 100)
  
  srad <-
    dplyr::filter(dat, variable == 'rsds') %$% terra::rast(f_list) 
  
  ws <-
    dplyr::filter(dat, variable == 'sfcWind') %$% terra::rast(f_list)  
  
  tmean <-
    dplyr::filter(dat, variable == 'tas') %$% terra::rast(f_list)  
  tmean <- tmean - 273.15
  
  tmax <-
    dplyr::filter(dat, variable == 'tasmax') %$% terra::rast(f_list)  
  tmax <- tmax - 273.15
  
  tmin <-
    dplyr::filter(dat, variable == 'tasmin') %$% terra::rast(f_list)  
  tmin <- tmin - 273.15
  
  elev <- ETo::get_elev_from_raster(terra::rast(ETo::tmean), 3)
  
  f_name <-
    dat %>% dplyr::select(model, pathway, metadata, d_name) %>%
    tidyr::unite(info, model, pathway, metadata) %>%
    dplyr::distinct() %>%
    dplyr::transmute(out = file.path(d_name, info)) %$%
    out %>%
    magrittr::extract(1)
  
  penman <- ETo::calc_etr_spatial(
    tmean = tmean,
    srad = srad,
    rh = rh,
    ws = ws,
    elev = elev,
    method = "penman"
  )
  
  hargreaves <- ETo::calc_etr_spatial(
    tmean = tmean,
    tmax = tmax,
    tmin = tmin,
    elev = elev,
    method = "hargreaves"
  )
  
  terra::writeRaster(
    penman,
    filename = glue::glue("{f_name}_penman.tif"),
    overwrite = TRUE
  )
  
  terra::writeRaster(
    hargreaves,
    filename = glue::glue("{f_name}_hargreaves.tif"),
    overwrite = TRUE
  )
  
  return(c(
    glue::glue("{f_name}_penman.tif"),
    glue::glue("{f_name}_hargreaves.tif")
  ))
}

clust <- new_cluster(10)
cluster_library(clust, c("magrittr"))
cluster_copy(clust, c("calc_eto_from_group"))

et_out <- tibble::tibble(f_list = f_list) %>%
  dplyr::mutate(
    f_name = tools::file_path_sans_ext(f_list) %>% basename,
    d_name = dirname(f_list)
  )  %>%
  tidyr::separate(
    f_name, c("model", "pathway", "metadata", "variable"), sep = "_"
  ) %>%
  dplyr::filter(!is.na(pathway)) %>%
  dplyr::filter(variable %in% v_list) %>%
  dplyr::group_by(model, pathway) %>%
  partition(clust) %>%
  dplyr::summarise(et_out = calc_eto_from_group(dplyr::cur_data_all()))
