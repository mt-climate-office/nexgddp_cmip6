from kerchunk.hdf import SingleHdf5ToZarr
import fsspec

url = "s3://nex-gddp-cmip6/NEX-GDDP-CMIP6/ACCESS-CM2/historical/r1i1p1f1/hurs/hurs_day_ACCESS-CM2_historical_r1i1p1f1_gn_1950.nc"

fs = fsspec.filesystem('s3', anon=True) #S3 file system to manage ERA5 files
flist = (fs.glob('s3://nex-gddp-cmip6/NEX-GDDP-CMIP6/ACCESS-CM2/historical/r1i1p1f1/hurs/hurs_day_ACCESS-CM2_historical_r1i1p1f1_gn_1950.nc')[:2])

fs2 = fsspec.filesystem('')  #local file system to save final jsons to

from pathlib import Path
import os
import ujson

so = dict(mode='rb', anon=True, default_fill_cache=False, default_cache_type='first') # args to fs.open()
# default_fill_cache=False avoids caching data in between file chunks to lowers memory usage.

def gen_json(file_url):
    with fs.open(file_url, **so) as infile:
        h5chunks = SingleHdf5ToZarr(infile, file_url, inline_threshold=300)
        # inline threshold adjusts the Size below which binary blocks are included directly in the output
        # a higher inline threshold can result in a larger json file but faster loading time
        variable = file_url.split('/')[-1].split('.')[0]
        month = file_url.split('/')[2]
        outf = f'{month}_{variable}.json' #file name to save json to
        with fs2.open(outf, 'wb') as f:
            f.write(ujson.dumps(h5chunks.translate()).encode());


for file in flist:
    gen_json(file)


