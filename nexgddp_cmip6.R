## CMIP6
library(magrittr)
dir.create(file.path("data-raw",
                     "nexgddp_cmip6"))
dir.create(file.path("data-derived",
                     "nexgddp_cmip6"))

st_rotate <- function(x){
  x2 <- (sf::st_geometry(x) + c(360,90)) %% c(360) - c(0,90)
  x3 <- sf::st_wrap_dateline(sf::st_set_crs(x2 - c(180,0), 4326)) + c(180,0)
  x4 <- sf::st_set_crs(x3, 4326)
  
  x <- sf::st_set_geometry(x, x4)
  
  return(x)
}

mt_bbox <- 
  mcor::mt_state_simple %>%
  sf::st_transform(4326) %>%
  st_rotate() %>%
  sf::st_bbox() %>%
  as.list()

mt_bbox$xmin %<>%
  magrittr::subtract(0.25)

mt_bbox$xmax %<>%
  magrittr::add(0.25)

mt_bbox$ymin %<>%
  magrittr::subtract(0.25)

mt_bbox$ymax %<>%
  magrittr::add(0.25)

# cmip6_bbox <-
#   sf::read_sf("data-raw/fort_peck_geospatial.gpkg",
#               layer = "reservation_bbox_10km_buffer") %>%
#   sf::st_transform(4326) %>%
#   st_rotate() %>%
#   sf::st_bbox() %>%
#   as.list()

cmip6_ncss <-
  thredds::tds_list_datasets("https://ds.nccs.nasa.gov/thredds/catalog/AMES/NEX/GDDP-CMIP6/catalog.html") %>%
  dplyr::filter(type == "catalog") %>%
  dplyr::filter(dataset %in% 
                  paste0(c("ACCESS-CM2",
                           "ACCESS-ESM1-5",
                           "CNRM-ESM2-1",
                           "EC-Earth3",
                           "GFDL-ESM4",
                           "GISS-E2-1-G",
                           "MIROC6",
                           "MPI-ESM1-2-HR",
                           "MRI-ESM2-0"), "/")) %>%
  dplyr::select(model = dataset,
                path) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(path = list(thredds::tds_list_datasets(path))) %>%
  tidyr::unnest(path) %>%
  dplyr::filter(type == "catalog") %>%
  dplyr::select(model,
                scenario = dataset,
                path) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(path = list(thredds::tds_list_datasets(path))) %>%
  tidyr::unnest(path) %>%
  dplyr::filter(type == "catalog") %>%
  dplyr::select(model,
                scenario,
                run = dataset,
                path) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(path = list(thredds::tds_list_datasets(path))) %>%
  tidyr::unnest(path) %>%
  dplyr::filter(type == "catalog") %>%
  dplyr::select(model,
                scenario,
                run,
                element = dataset,
                path) %>%
  dplyr::filter(element %in% c("tasmin/","tasmax/","sfcWind/","pr/","hurs/")) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(path = list(thredds::tds_list_datasets(path))) %>%
  tidyr::unnest(path) %>%
  dplyr::select(model,
                scenario,
                run,
                element,
                dataset) %>%
  dplyr::filter(stringr::str_detect(dataset, ".nc")) %>%
  dplyr::mutate(dplyr::across(model:element, ~stringr::str_remove(.x, "/"))) %>%
  dplyr::mutate(year = stringr::str_extract(dataset, "\\d{4}.nc") %>%
                  stringr::str_remove(".nc") %>%
                  as.integer()) %>%
  dplyr::select(model,
                scenario,
                run,
                year,
                element,
                dataset) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    ncss = 
      paste0("https://ds.nccs.nasa.gov/thredds/ncss/AMES/NEX/GDDP-CMIP6/",
             model,"/", 
             scenario, "/",
             run,"/",
             element,"/",
             dataset) %>%
      httr::modify_url(
        query = list(
          var = element,
          north = mt_bbox$ymax,
          west = mt_bbox$xmin,
          east = mt_bbox$xmax,
          south = mt_bbox$ymin,
          disableProjSubset = "on",
          horizStride = 1,
          time_start = paste0(year, "-01-01"),
          time_end = paste0(year, "-12-31"),
          timeStride = 1,
          addLatLon = TRUE
        ))
  )


get_ncss <- function(x, out.path){
  
  if(file.exists(out.path))
    return(out.path)
  
  out <- httr::GET(x, httr::write_disk(out.path,
                                       overwrite = TRUE))
  return(out.path)
}

clust <- multidplyr::new_cluster(10)
multidplyr::cluster_copy(clust, "get_ncss")

cmip6_ncss %<>%
  dplyr::rowwise() %>%
  multidplyr::partition(clust) %>%
  dplyr::mutate(rast = get_ncss(ncss, out.path = file.path("data-raw", 
                                                           "nexgddp_cmip6",
                                                           dataset))) %>%
  dplyr::collect()

rm(clust)
gc()
gc()

read_cmip6 <- 
  function(x){
    terra::rast(x) %T>%
      terra::set.ext(terra::ext(raster::brick(x[1]))) %>%
      terra::rotate()
  }

cmip6_rasts <-
  cmip6_ncss %>%
  dplyr::group_by(model, scenario, run, element) %>%
  dplyr::summarise(rast = list(c(rast))) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(rast = list(read_cmip6(rast)))
  
write_cmip6 <- 
  function(x, out_file){
    terra::writeRaster(x,
                       filename = out_file,
                       overwrite = TRUE, 
                       gdal = c("COMPRESS=DEFLATE", "of=COG"),
                       memfrac = 0.9)
    return(out_file)
  }



cmip6_rasts2 <-
  cmip6_rasts %>%
  dplyr::arrange(element, scenario) %>%
  dplyr::mutate(rast = write_cmip6(rast, 
                                   out_file = 
                                     file.path("data-derived",
                                               "nexgddp_cmip6",
                                               paste0(model, "_",
                                                      scenario, "_",
                                                      run, "_",
                                                      element, ".tif"))))


# 
# 
# test_ncss$ncss[[1]] %>%
#   httr::GET(httr::write_disk("data-raw/nexgddp_cmip6/tasmin_day_MRI-ESM2-0_ssp585_r1i1p1f1_gn_2100.nc",
#                              overwrite = TRUE))
# 
# out <- 
#   terra::rast("data-raw/nexgddp_cmip6/tasmin_day_MRI-ESM2-0_ssp585_r1i1p1f1_gn_2100.nc") %T>%
#   terra::set.ext(terra::ext(raster::brick("data-raw/nexgddp_cmip6/tasmin_day_MRI-ESM2-0_ssp585_r1i1p1f1_gn_2100.nc")))
