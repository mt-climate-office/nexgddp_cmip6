# nexgddp_cmip6
Data download for the NASA NEXGDDP CMIP6 Downscaled Climate Product for Montana and CONUS

```{bash}
docker compose up -d
docker exec -it nexgddp_cmip6 bash
docker exec -d nexgddp_cmip6 bash -c "cd /root; Rscript cmip6-conus.R"
```
