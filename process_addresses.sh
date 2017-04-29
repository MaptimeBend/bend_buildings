# This script will build up a postgis database with buildings and addresses

# Create database buildings, assumes postgres is installed, user postgres is available, and db is listening at localhost:5432
createdb buildings

# Drop the table if it exists
psql -d buildings --command='DROP TABLE IF EXISTS public.buildings, public.buildings_centroids, public.address, public.taxlots'

# Add postgis extension if it's not already added
psql -d buildings -c "CREATE EXTENSION postgis;"

# Get info on our original dataset
ogrinfo -so data/building_footprints2004_intlfeet.shp building_footprints2004_intlfeet

# Create a scratch directory
mkdir data_processing

# Add buildings
echo "Adding buildings..."
ogr2ogr -f PostgreSQL PG:"host=localhost port=5432 dbname=buildings user=postgres" data/building_footprints2004_intlfeet.shp -sql "SELECT FID AS id, CAST(elevation AS numeric(10,3)) AS orig_el_ft FROM building_footprints2004_intlfeet" -nln buildings -t_srs http://spatialreference.org/ref/epsg/32127/ -progress
echo "Added buildings"

# Add taxlots
echo "Fetching taxlots..."
ogr2ogr -f PostgreSQL PG:"host=localhost port=5432 dbname=buildings user=postgres" "https://opendata.arcgis.com/datasets/28019431cced49849cb4b1793b075bf1_2.geojson" -nln taxlots -t_srs http://spatialreference.org/ref/epsg/32127/ -select 'taxlot' -progress
echo "Added taxlots"

# Add address table
echo "Fetching address table..."
ogr2ogr -f PostgreSQL PG:"host=localhost port=5432 dbname=buildings user=postgres" "https://opendata.arcgis.com/datasets/aea94004ae8c49e6a6dec394522677ad_1.geojson" -nln address -t_srs http://spatialreference.org/ref/epsg/32127/ -select 'taxlot, house_number, direction, street_name, street_type, zip' -progress
echo "Added address table"

# Build indexes on taxlots add addresses by the taxlot column
psql -d buildings --command="CREATE INDEX ON taxlots (taxlot)"
psql -d buildings --command="CREATE INDEX ON address (taxlot)"
echo "Indexed taxlots and addresses"

# Add new columns to taxlots for address data
echo "Adding columns to taxlots"
psql -d buildings --command='ALTER TABLE taxlots ADD COLUMN housenumber varchar(15), ADD COLUMN street varchar(50), ADD COLUMN postcode varchar(20), ADD COLUMN building varchar(20);'

# Join addresses to taxlots
echo "Joining addresses to taxlots"
psql -d buildings --command="UPDATE taxlots a SET (housenumber, street, postcode) = (b.house_number, CONCAT_WS(' ', b.direction, b.street_name, b.street_type), b.zip) FROM address b WHERE a.taxlot = b.taxlot;"

# Add new columns to buildings
echo "Adding columns to buildings"
psql -d buildings --command='ALTER TABLE buildings ADD COLUMN housenumber varchar(15), ADD COLUMN street varchar(50), ADD COLUMN postcode varchar(20), ADD COLUMN building varchar(20);'

# Create centroids table for spatial join
echo "Creating temp centroid table"
psql -d buildings --command='CREATE TABLE buildings_centroids AS SELECT b.ogc_fid AS ogc_fid, ST_Centroid(b.wkb_geometry) AS centroid FROM buildings b;'

# Add new columns to buildings_centroids
echo "Adding columns to temp centroid table"
psql -d buildings --command='ALTER TABLE buildings_centroids ADD COLUMN housenumber varchar(15), ADD COLUMN street varchar(50), ADD COLUMN postcode varchar(20), ADD COLUMN building varchar(20);'

# Join using spatial join
echo "Executing spatial join on building centroids and taxlots"
psql -d buildings --command='UPDATE buildings_centroids a SET (housenumber, street, postcode) = (b.housenumber, b.street, b.postcode) FROM taxlots b WHERE ST_Within(a.centroid, b.wkb_geometry);'

# Join the address info back to the buildings table
echo "Copying address info back to buildings"
psql -d buildings --command='UPDATE buildings a SET (housenumber, street, postcode) = (b.housenumber, b.street, b.postcode) FROM buildings_centroids b WHERE a.ogc_fid = b.ogc_fid;'

echo "Addresses added"

echo "Removing temp tables"
psql -d buildings --command="DROP TABLE IF EXISTS public.buildings_centroids, public.address, public.taxlots"
