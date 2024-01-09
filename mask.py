import argparse
import rasterio
from rasterio.mask import mask
import geopandas as gpd
from shapely.geometry import mapping


def mask_raster_with_geojson(input_raster_path, mask_geojson_path, output_path):
    with rasterio.open(input_raster_path) as src:
        # Read the mask GeoJSON using geopandas
        mask_data = gpd.read_file(mask_geojson_path)

        # Reproject the mask to match the CRS (Coordinate Reference System) of the raster
        mask_data = mask_data.to_crs(src.crs)

        # Convert the mask geometry to a GeoJSON-like format
        geoms = mask_data.geometry.values.tolist()
        geoms = [mapping(geom) for geom in geoms]

        # Apply the mask to the raster
        masked_image, transform = mask(src, geoms, crop=True, all_touched=True)

        # Get metadata of the masked raster
        meta = src.meta.copy()

        # Update metadata with new dimensions, transform, and CRS
        meta.update({
            'height': masked_image.shape[1],
            'width': masked_image.shape[2],
            'transform': transform,
            'nodata': src.nodata,
            'crs': src.crs
        })

    # Write the masked raster to a new file
    with rasterio.open(output_path, 'w', **meta) as dst:
        dst.write(masked_image)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Mask a GeoTIFF using a GeoJSON.')
    parser.add_argument('input_raster', help='Input GeoTIFF file path')
    parser.add_argument('mask_geojson', help='Input GeoJSON file path for masking')
    parser.add_argument('output_path', help='Output path for the masked GeoTIFF')
    args = parser.parse_args()

    mask_raster_with_geojson(args.input_raster, args.mask_geojson, args.output_path)
