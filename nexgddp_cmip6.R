cmip6_files <- 
  readr::read_csv("https://nex-gddp-cmip6.s3-us-west-2.amazonaws.com/gddp-cmip6-files.csv") %>%
  dplyr::mutate(dataset = tools::file_path_sans_ext(basename(fileURL))) %>%
  tidyr::separate_wider_delim(dataset, 
                              names = c("element", "timestep", "model", "scenario", "run", "type", "year"), 
                              delim = "_",
                              cols_remove = FALSE) %>%
  dplyr::mutate(dataset = paste0(dataset, ".nc")) %>% 
  dplyr::select(model, scenario, run, year, element, dataset, aws = fileURL) %>%
  dplyr::filter(model %in% 
                  c("ACCESS-ESM1-5",
                    "CNRM-ESM2-1",
                    "EC-Earth3",
                    "GFDL-ESM4",
                    "GISS-E2-1-G",
                    "MIROC6",
                    "MPI-ESM1-2-HR",
                    "MRI-ESM2-0")) %>%
  dplyr::arrange(model, scenario, run, year, element, dataset)

st_rotate <- function(x){
  x2 <- (sf::st_geometry(x) + c(360,90)) %% c(360) - c(0,90)
  x3 <- sf::st_wrap_dateline(sf::st_set_crs(x2 - c(180,0), 4326)) + c(180,0)
  x4 <- sf::st_set_crs(x3, 4326)
  
  x <- sf::st_set_geometry(x, x4)
  
  return(x)
}

get_ncss <- function(x, out.path){
  
  if(file.exists(out.path))
    return(out.path)
  
  out <- httr::GET(x, httr::write_disk(out.path,
                                       overwrite = TRUE))
  return(out.path)
}

options(timeout = max(300, getOption("timeout")))

get_cmip6 <- 
  function(x, outdir){
    x %<>%
      sf::st_transform(4326) %>%
      st_rotate() %>%
      sf::st_bbox() %>%
      as.list()
    
    clust <- multidplyr::new_cluster(10)
    multidplyr::cluster_library(clust, "magrittr")
    multidplyr::cluster_copy(clust, c("get_ncss", "outdir"))
    
    out <-
      cmip6_files %>%
      dplyr::filter(!file.exists(file.path(outdir, dataset))) %>%
      dplyr::rowwise() %>%
      multidplyr::partition(clust) %>%
      dplyr::mutate(
        rast = get_ncss(
          httr::modify_url(
            paste0("https://ds.nccs.nasa.gov/thredds/ncss/AMES/NEX/GDDP-CMIP6/",
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
            )), 
          out.path = file.path(outdir,
                               dataset))) %>%
      dplyr::collect()
    
    rm(clust)
    gc()
    gc()
    return(out)
  }

get_aws <- function(x, mask, out.path){
  
  if(file.exists(out.path))
    return(out.path)
  
  tmpout <- tempfile(fileext = ".nc")
  
  download.file(x,
                destfile = tmpout,
                quiet = TRUE,
                mode = "wb")
  
  out <- 
    terra::rast(tmpout) %>%
    terra::crop(mask, 
                snap = "out", 
                mask = TRUE) 
  
  terra::writeCDF(out,
                  varname = terra::varnames(terra::rast(tmpout))[[1]],
                  longname = terra::longnames(terra::rast(tmpout))[[1]],
                  unit = terra::units(terra::rast(tmpout))[[1]],
                  filename = out.path,
                  compression = 6,
                  overwrite = TRUE)
  
  unlink(tmpout)
  
  return(out.path)
}


get_cmip6_aws <-
  function(x, outdir){
    x %<>%
      sf::st_transform(4326) %>%
      st_rotate()
    
    clust <- multidplyr::new_cluster(10)
    multidplyr::cluster_library(clust, "magrittr")
    multidplyr::cluster_copy(clust, c("get_aws", "outdir"))
    
    out <-
      cmip6_files %>%
      dplyr::rowwise() %>%
      multidplyr::partition(clust) %>%
      dplyr::mutate(
        rast = tryCatch(
          get_aws(
            aws,
            mask = x,
            out.path = file.path(outdir,
                                 dataset)),
          error = function(e){return(NA)}
          
        )
      ) %>%
      dplyr::collect()
    
    rm(clust)
    gc()
    gc()
    return(out)
  }

