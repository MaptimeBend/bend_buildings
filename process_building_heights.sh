
# Export a simple geojson to use with rasterio
echo "Exporting geojson to use with rasterio"
ogr2ogr -f GeoJSON data_processing/temp.json PG:"host=localhost port=5432 dbname=buildings user=postgres" -sql 'SELECT id, wkb_geometry FROM buildings' -t_srs http://spatialreference.org/ref/epsg/32127/

# Perform zonal stats using rasterio
echo "Performing zonal statistics"
rio zonalstats -r data_processing/temp/height/height.vrt --prefix "height" --stats "max median" data_processing/temp.json > data_processing/temp_heights.geojson

# Import the height data into postgis
echo "Importing height data file"
ogr2ogr -f PostgreSQL PG:"host=localhost port=5432 dbname=buildings user=postgres" data_processing/temp_heights.geojson -sql "SELECT id AS id, heightmax AS height_max, heightmedian AS height_median FROM OGRGeoJSON" -nln buildings_height_temp -progress

# Copy height values to buildings table
echo "Copying height data to buildings table"
psql -d buildings --command='ALTER TABLE buildings ADD COLUMN height_max numeric(5,2), ADD COLUMN height_median numeric(5,2);'
psql -d buildings --command='UPDATE buildings a SET (height_max, height_median) = (b.height_max, b.height_median) FROM buildings_height_temp b WHERE a.id = b.id;'

# Remove temp tables
echo "Removing temp files"
psql -d buildings --command='DROP TABLE IF EXISTS public.buildings_height_temp'
rm data_processing/temp.json
rm data_processing/temp_heights.geojson

echo "Exporting demo file"
ogr2ogr -f GeoJSON demo/buildings_042817.geojson PG:"host=localhost port=5432 dbname=buildings user=postgres" -sql 'SELECT id, wkb_geometry, housenumber, street, postcode, height_median AS height FROM buildings' -t_srs http://spatialreference.org/ref/epsg/4326/
