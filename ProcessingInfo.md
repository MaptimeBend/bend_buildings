# Processing instructions to create Bend buildings OSM file from public data

## Getting started

Clone this repo. You'll find `README.md`, a `/data` directory, the `license.txt` file that contains the City of Bend release to use their data, a `demo` folder, which contains a web map that displays the latest dataset and a `final_osm` folder, which contains the final OSM file and other accompanying data produced using these instructions. While the `final_osm` folder should contain the information needed, this tutorial is provided as documentation for how the final files were produced and can be reproduced. No black boxes.

## Requirements:

- WGET `brew install wget`
- GDAL `brew install gdal`
- liblas `brew install liblas --with-laszip`
- points2grid `brew install points2grid`
<!-- - ~StarSpan~ -->
- Rasterio `pip install rasterio`
- Rasterstats `pip install rasterstats`

I'll go into each of the above as they come up.

I used macOS when writing this tutorial, but most of the instructions should work from any command line. Installing using homebrew won't, though.

## Existing dataset

The Bend buildings footprint shapefile comes from the City of Bend. Although they have not yet publicly available on their site, we are hosting it in this repo in the /data directory.

We'll be doing most of our geospatial processing using GDAL. I like using [Homebrew](http://brew.sh/) to manage packages on macOS. [NuGet](https://www.nuget.org/) is a nice Windows equivalent, but you'll have to figure out equivalent commands. If you want to build stuff from source, go right ahead, but this tutorial won't cover that.

Install GDAL:

```
brew install gdal
```

This gives you access to all of the GDAL commands in the command line. ([Here's a great GDAL cheat sheet](https://github.com/dwtkns/gdal-cheat-sheet))

Let's take a look at the info for our building footprints shapefile:

```
ogrinfo -so data/building_footprints2004_intlfeet.shp building_footprints2004_intlfeet
```

This gives us some important information, including feature count, extent, projection and column info.

```
Layer name: building_footprints2004_intlfeet
Geometry: Polygon
Feature Count: 36213
Extent: (4690402.137375, 848970.889309) - (4739228.270561, 896476.467954)
Layer SRS WKT:
PROJCS["NAD_1983_StatePlane_Oregon_South_FIPS_3602_Feet_Intl",
    GEOGCS["GCS_North_American_1983",
        DATUM["North_American_Datum_1983",
            SPHEROID["GRS_1980",6378137.0,298.257222101]],
        PRIMEM["Greenwich",0.0],
        UNIT["Degree",0.0174532925199433]],
    PROJECTION["Lambert_Conformal_Conic_2SP"],
    PARAMETER["False_Easting",4921259.842519685],
    PARAMETER["False_Northing",0.0],
    PARAMETER["Central_Meridian",-120.5],
    PARAMETER["Standard_Parallel_1",42.33333333333334],
    PARAMETER["Standard_Parallel_2",44.0],
    PARAMETER["Latitude_Of_Origin",41.66666666666666],
    UNIT["Foot",0.3048]]
FID_: Integer (9.0)
ENTITY: String (16.0)
HANDLE: String (16.0)
LAYER: String (254.0)
COLOR: Integer (9.0)
LINETYPE: String (254.0)
ELEVATION: Real (19.11)
THICKNESS: Real (19.11)
TEXT: String (254.0)
```

This dataset is in a very accurate local projection, but really only good for southern Oregon. We'll need to make sure all of our datasets are in the same projection before performing some geospatial processing later, but we'll leave it for now.

We have 36,213 entries. This dataset was originally created for the city in 2004. That might seem old, but it's approximately 30,000 more buildings than are in OSM now. We'll merge our dataset with the existing OSM buildings for Bend before our import.

The fields included in this shapefile suggest that this dateset was originally exported from a CAD drawing program, and won't be useful to us for the most part. Let's copy the shapefile and exclude everything but the `ELEVATION` field. (We'll calculate the base elevation from LIDAR later, but we'll keep this field for comparison for now.)

_Before we start creating a bunch of temp data, create a new folder called `data_processing` in the main repo and add it to [your `.gitignore` file](https://help.github.com/articles/ignoring-files/). We'll be filling this folder with lots of (sometimes enormous) scratch files, and we don't really want to track them in github._

Make our processing folder and enter it:

```
mkdir data_processing
```

Now lets make that new shapefile:

```
ogr2ogr data_processing/building_footprints.shp data/building_footprints2004_intlfeet.shp -sql "SELECT FID AS id, CAST(elevation AS numeric(10,3)) AS orig_el_ft FROM building_footprints2004_intlfeet" -progress -overwrite
```

Here's what's happening in that command (I won't break down all of them, just this one since it's kind of a beast):

- `ogr2ogr` This is the GDAL tool that transforms data.
- `data_processing/building_footprints.shp data/building_footprints2004_intlfeet.shp` ogr2ogr accepts output.shp input.shp as arguments.
- `-sql` This is a flag that accepts a string of SQL. In this case, we're selecting the `elevation` field from our input and casting it as a numeric value with a width of 10 and a precision of 3, then names it as `orig_el_ft` (original elevation in feet)
- `-progress` Shows the progress in the terminal, not required
- `-overwrite` Overwrites the output file if it already exists, not required but nice if you're executing a command multiple

Now we have a fresh shapefile with just the original elevation in feet for each building footprint.

## Adding building heights

Bend has pretty complete LIDAR coverage from 2010 via [DOGAMI](http://www.oregongeology.org/sub/lidardataviewer/index.htm). LIDAR is a way to collect a dense point cloud file that can be used to extract meaningful information about landscapes at a very high resolution. We'll use the raw LIDAR files (.las) to create high-resolution [DSM and DTM](https://en.wikipedia.org/wiki/Digital_elevation_model) images that we can use to extract elevations and building heights. We'll then create tiled versions of those to use during OSM import sessions as a heads-up comparison tool.

### Determine required LIDAR dataset

DOGAMI's LIDAR viewer allows the user to download derived products (DTMs, etc), but we want the raw to produce some higher-resolution products. The raw data is hosted by the [NOAA Digital Coast](https://coast.noaa.gov/htdata/lidar1_z/geoid12a/data/) project.

LIDAR coverage is [kind of funny shaped](https://coast.noaa.gov/dataviewer/#/lidar/search/where:ID=1452) for the Bend area, and the entire dataset is far more than we need. Despite the odd coverage, the `.laz` files (a compressed version of `.las`) are available in chunks based on a regular grid. NOAA provides a [shapefile](https://coast.noaa.gov/htdata/lidar1_z/geoid12a/data/1452/tileindex.zip
) that shows the tile index, and contains direct links to the `.laz` files for each tile as a field.

Here I'm going to introduce you to [Wget](https://www.gnu.org/software/wget/). There are lots of ways to download a file via the command line, but Wget is one of the more robust tools I've used. We'll use it again in later steps.

Install Wget:

```
homebrew install wget
```

Download the LIDAR tile index shapefile to our `data_processing` folder:

```
wget https://coast.noaa.gov/htdata/lidar1_z/geoid12a/data/1452/tileindex.zip -P data_processing
```

Now let's extract the zip:

```
unzip data_processing/tileindex.zip -d data_processing
```

And take a look with `ogrinfo`:

```
ogrinfo -so data_processing/2010_OR_DOGAMI_Newberry_index.shp 2010_OR_DOGAMI_Newberry_index

INFO: Open of `data_processing/2010_OR_DOGAMI_Newberry_index.shp'
      using driver `ESRI Shapefile' successful.

Layer name: 2010_OR_DOGAMI_Newberry_index
Geometry: Polygon
Feature Count: 1021
Extent: (-121.487667, 43.537764) - (-121.066001, 44.122480)
Layer SRS WKT:
GEOGCS["NAD83(NSRS2007)",
	    DATUM["Hungarian_Datum_1909",
        SPHEROID["GRS_1980",6378137,298.257222101]],
    PRIMEM["Greenwich",0],
    UNIT["Degree",0.017453292519943295]]
Index: Integer (10.0)
Name: String (60.0)
URL: String (117.0)

```

1021 features! That's a lot of LIDAR data, and we only need some of them. And look, there's a `URL` field that points directly at the `.laz` files we need. What we need to do is figure out which of those `.laz` files we need, and then download and process each one.

To do that, we'll start by using `ogr2ogr` to clip the LIDAR `tile_index.shp` file using the `building_footprints.shp` layer extents. But first, we'll need to make sure they're in the same coordinate system. We'll use `EPSG:4326`.

Convert the buildings:

```
ogr2ogr data_processing/buildings_4326.shp -t_srs "EPSG:4326" data_processing/building_footprints.shp
```

Convert the tile index:

```
ogr2ogr data_processing/lidar_index_4326.shp -t_srs "EPSG:4326" data_processing/2010_OR_DOGAMI_Newberry_index.shp
```

Now that both are in the same coordinate system, we can properly clip. Let's grab the extent of the buildings layer:

```
ogrinfo data_processing/buildings_4326.shp buildings_4326 | grep Extent
```

Thus revealing: `Extent: (-121.378524, 43.993228) - (-121.192770, 44.123710)`

Now we can clip the tile index shapefile by that bounding box:

```
ogr2ogr -f "ESRI Shapefile" data_processing/lidar_index_subset.shp data_processing/lidar_index_4326.shp -clipsrc -121.192770 44.123710 -121.378524 43.993228
```

That gives us a shapefile that is essentially a list of the LIDAR data we'll need, with URLs to their locations. _An alternative to using a bounding box would be to use the buildings layer itself as a clipping source, or an sql query to spatially select the overlapping features, but a bounding box is simpler in this case._

Finally, let's convert that into a `.csv` file that Wget can iterate over.

```
ogr2ogr -f "CSV" data_processing/lidar_urls.csv data_processing/lidar_index_subset.shp -sql "SELECT url FROM lidar_index_subset"
```

Let's confirm:

```
vim data_processing/lidar_urls.csv
```

[Vim](http://vimsheet.com/) is a command-line text editor. It's a pain to learn but sometimes it's nice to be able to do basic reading and editing of text and code files without opening another application.

It looks like there are some extraneous double quotation marks in the file that will hose the wget command in the next step. Let's use Vim to get rid of them by globally finding and replacing them with nothing. In vim, type `:%s/"//g` and press Enter. Vim should inform you that a bunch of substitutions have been made.

Once you're satisfied that our file is correct, you can close Vim by typing `:q` and then pressing Enter.

<!-- There's got to be a way with wget or gdal to skip this step -->

### Download LIDAR files

_**Note:** This step is going to download just under 5GB of data to your computer. Make sure you have a good internet connection and enough disk space before starting._

This should be as simple as:

```
wget -P data_processing/raw_lidar -i data_processing/lidar_urls.csv
```

Wget is very helpful in that it informs you what is going on with each download. This step acquires about 125 rather large files, so you can see why we don't include them in the Github repo to begin with.

### Processing LIDAR

For each LIDAR dataset, we'll:

1. Read the LIDAR file (.laz)
2. Filter out the points we're looking for
3. Interpolate the filtered points and write to a raster file

First, our tools:

- liblas `brew install liblas --with-laszip` (this includes las2las)
- points2grid `brew install points2grid`

The tool we're going to use to create our raster files, points2grid, needs uncompressed LAS files for input. So we'll first decompress our LAZ file into a temp folder:

```
mkdir data_processing/temp
las2las -i data_processing/raw_lidar/20100528_43121h2101.laz -o data_processing/temp/20100528_43121h2101.laz.las;
```

Next, we'll use points2grid to both filter out the last returns and create our raster files, which will be in ASC, or arc grid, format.

The points2grid command uses the given resolution (in this case .00001 of a degree) to set the pixel size. <!-- Convert to UTM? --> Then it examines all lidar points that fall within each pixel and gives us a single interpolated value of all of the points. The command can produce maximum, minimum, median, average [inverse difference weighted (IDW)](http://help.arcgis.com/en/arcgisdesktop/10.0/help/index.html#//00310000002m000000) rasters. We'll be creating minimum and IDW rasters for use in our calculations. IDW will give us a good, sharply-defined building outline and generally reliable height fields. Our minimum raster will be used for calculating the ground level around each building, since lidar returns should generally never be lower than the ground. :smile:


```
mkdir data_processing/rasters
mkdir data_processing/rasters/idw
mkdir data_processing/rasters/min

points2grid -i data_processing/temp/20100528_43121h2101.laz.las --last_return_only --resolution .00001 --idw -o data_processing/rasters/idw/20100528_43121h2101.laz.las --output_format arc;

points2grid -i data_processing/temp/20100528_43121h2101.laz.las --last_return_only --resolution .00001 --min -o data_processing/rasters/min/20100528_43121h2101.laz.las --output_format arc;

```

Additionally, we can remove our temp file with `rm data_processing/temp/20100528_43121h2101.laz.las`.

Now, just repeat that 125 more times!

Or, we can use a bash script to loop through all of the .laz files in our `raw_lidar` folder and complete each action:

```
for f in data_processing/raw_lidar/*.laz;
	do
		name=${f##*/}
		las2las -i $f -o temp/${name}.las;
	    points2grid -i data_processing/temp/${name}.las --last_return_only --resolution .00001 --idw -o data_processing/rasters/idw/${name} --output_format arc;
	    points2grid -i data_processing/temp/${name}.las --last_return_only --resolution .00001 --min -o data_processing/rasters/min/${name} --output_format arc;
		rm data_processing/temp/${name}.las
done
```

Finally, let's convert our new rasters into merged files.

```
rio merge data_processing/rasters/idw/*.asc data_processing/rasters/idw/idw_merged.asc
rio merge data_processing/rasters/min/*.asc data_processing/rasters/min/min_merged.asc
```

We now have the raster info we need to perform all of our calculations.

### Calculate building heights

#### Create a buffer file

First, reproject our buildings to a meter-based projection (degrees are not great for buffering):

```
ogr2ogr data_processing/temp/buildings_meters.shp -t_srs "EPSG:26910" data_processing/buildings_4326.shp
```

Now create a 1m buffer:

```
ogr2ogr data_processing/temp/building1m.shp data_processing/temp/buildings_meters.shp buildings_meters -dialect sqlite -sql "SELECT ST_Buffer( geometry, 1 ), * FROM 'buildings_meters'"
```

And a 2m buffer:

```
ogr2ogr data_processing/temp/building2m.shp data_processing/temp/buildings_meters.shp buildings_meters -dialect sqlite -sql "SELECT ST_Buffer( geometry, 2 ), * FROM 'buildings_meters'"
```

And get the difference between the 2m buffer using the 1m buffer (this took a while on my machine):

<!-- Adding a spatial index first might help? Haven't tried yet -->

```
ogr2ogr -f "GeoJSON" data_processing/building_buffer.geojson data_processing/temp/building2m.shp -dialect sqlite \
-sql "SELECT ST_Difference(a.Geometry, b.Geometry) AS Geometry, a.id \
FROM building2m a LEFT JOIN 'data_processing/temp/building1m.shp'.building1m b USING (id) WHERE a.Geometry != b.Geometry"
```

#### Calculate the zonal statistics for buffer and buildings

Note that we output GeoJSON in the above step. The tool we're using for **zonal statistics**, RasterStats, requires GeoJSON as input.

Now let's create a GeoJSON copy of the buildings layer:

```
ogr2ogr -f "GeoJSON" data_processing/buildings_4326.geojson data_processing/buildings_4326.shp
```

And reproject our buffer to EPSG:4326:

```
ogr2ogr -f "GeoJSON" data_processing/building_buffer_4326.geojson -t_srs "EPSG:4326" data_processing/building_buffer.geojson
```

Let's get the zonal stats of our buildings:

```
rio zonalstats -r data_processing/rasters/idw/idw_merged.asc --prefix "building_el_" --stats "max median" data_processing/buildings_4326.geojson > data_processing/building_elevation.geojson
```

And the zonal status of our buffer:

```
rio zonalstats -r data_processing/rasters/min/min_merged.asc --prefix "buffer_el_" --stats "min median" data_processing/building_buffer_4326.geojson > data_processing/buffer_elevation.geojson
```

#### Calculate building heights

And now, finally, we create a new dataset with the difference between our building elevation and our buffer elevation:

Start by creating a dataset with all of our statistical fields by joining our two geojson files based on their `id` field. This will be easiest if we convert them back to shapefiles and create an index on the `id` field:

```
ogr2ogr -f "ESRI Shapefile" data_processing/building_el.shp data_processing/building_elevation.geojson -progress -overwrite
ogr2ogr -f "ESRI Shapefile" data_processing/buffer_el.shp data_processing/buffer_elevation.geojson -progress

ogrinfo data_processing/building_el.shp -sql "CREATE INDEX ON building_el USING id"
ogrinfo data_processing/buffer_el.shp -sql "CREATE INDEX ON buffer_el USING id"
```

The converstion to shapefile will truncate our column names, and gdal should tell you:

```
Warning 6: Normalized/laundered field name: 'building_el_max' to 'building_e'
Warning 6: Normalized/laundered field name: 'building_el_median' to 'building_1'

...

Warning 6: Normalized/laundered field name: 'buffer_el_min' to 'buffer_el_'
Warning 6: Normalized/laundered field name: 'buffer_el_median' to 'buffer_e_1'
```

Let's just note that. We'll need to know which is which later.


Then create the joined shapefile:

```
ogr2ogr -f "ESRI Shapefile" data_processing/building_el_join.shp data_processing/building_el.shp -dialect sqlite -sql "SELECT * FROM building_el a LEFT JOIN 'data_processing/buffer_el.shp'.buffer_el b ON a.id = b.id" -overwrite -progress
```

Now for some math.

First, lets add a field to contain our building height. We want it to be a floating point with two decimal points of precision. We'll call it `height`.

```
ogrinfo data_processing/building_el_join.shp -sql "ALTER TABLE building_el_join ADD COLUMN height numeric(6,2)"
```

Remember how we included the `orig_el_ft` field in our table? That's a height field for each building recorded in feet from the original dataset. Let's create another column that we can use to convert those values to meters and compare to our lidar-derived values.

```
ogrinfo data_processing/building_el_join.shp -sql "ALTER TABLE building_el_join ADD COLUMN orig_el_m numeric(7,3)"
```

Math time. The [OpenStreetMap wiki tells us](http://wiki.openstreetmap.org/wiki/Key:height) that the `height` tag should be the distance between the **maximum height** of the building and the **lowest point at the bottom** where the building meets the terrain. So we should be able to subtract our **building max** field from our **buffer min** field to get just about the most accurate lidar-derived building height possible, right? That would be true if there were no trees or other obstructions that stood over the top of a building. So instead of using the **max** value from our zonal stats, we'll use the **median**, which should give us a better representation of the actual top of each building. Additionally, our original height in meters should be the value in feet multiplied by 0.305. These commands will give you some warnings saying values weren't successfully written, but that's just due to have to cut off a bunch of decimal points from the original values.

```
ogrinfo data_processing/building_el_join.shp -dialect SQLite -sql "UPDATE building_el_join SET height = building_1 - buffer_el_"

ogrinfo data_processing/building_el_join.shp -dialect SQLite -sql "UPDATE building_el_join SET orig_el_m = orig_el_ft * 0.305"

```

We now have a shapefile with a height value for all 36K+ buildings in Bend. Now, it's not perfect. The building footprints were created in 2004 an the lidar was flown in 2010. Any difference between a building between those dates could result in funky data, which is why we'll be doing some quality assurance during our mapathon.

Let's tear off a geojson file that we can stash in our demo folder for display on a web map: (Note: You'll need to delete the original demo geojson before running this command)

```
ogr2ogr -f "GeoJSON" demo/buildings.geojson data_processing/building_el_join.shp -sql "SELECT id AS id, height AS height FROM building_el_join" -progress
```

And now let's fire up the demo page:

```
cd demo
python -m SimpleHTTPServer 8000
```

Now open a browser and navigate to http://localhost:8000.


## Building addresses

[Deschutes County's Open Data Portal](http://data.deschutes.org/) offers an up-to-date dataset of [all taxlots](http://data.deschutes.org/datasets/28019431cced49849cb4b1793b075bf1_2) in Bend. The portal also offers an up-to-date [data file of addresses](http://data.deschutes.org/datasets/aea94004ae8c49e6a6dec394522677ad_1) for each taxlot.

We'll download both files, join them based on taxlot ID, and then perform a spatial join to attach address information to buildings based on their taxlot. Fun!

First the taxlots dataset:

```
ogr2ogr -f "ESRI Shapefile" data_processing/taxlots.shp "http://data.deschutes.org/datasets/28019431cced49849cb4b1793b075bf1_2.geojson" OGRGeoJSON
```

Then the assessor info table: (This will not have a geometry field, but we'll want an index for our later join.)

```
ogr2ogr -f "ESRI Shapefile" data_processing/addresses.dbf "http://data.deschutes.org/datasets/aea94004ae8c49e6a6dec394522677ad_1.geojson" OGRGeoJSON
```

Now let's go ahead and create indexes on the both datasets:

```
ogrinfo data_processing/taxlots.shp -sql "CREATE INDEX ON taxlots USING taxlot"
ogrinfo data_processing/addresses.dbf -sql "CREATE INDEX ON addresses USING taxlot"
```

Now to join them (this one takes a while):

<!-- Could reduce this dataset to only taxlots in Bend before? -->

```
ogr2ogr -f "ESRI Shapefile" data_processing/taxlots_addresses_joined.shp data_processing/taxlots.shp -dialect sqlite -sql "SELECT * FROM taxlots a LEFT JOIN 'data_processing/addresses.dbf'.addresses b ON a.taxlot = b.taxlot" -overwrite -progress
```

Now let's add spatial indexes to our taxlots and buildings:

```
ogrinfo data_processing/taxlots_addresses_joined.shp -sql "CREATE SPATIAL INDEX ON taxlots_addresses_joined"
ogrinfo data_processing/building_el_join.shp -sql "CREATE SPATIAL INDEX ON building_el_join"
```

Our joined taxlots shapefile has the following fields:

```
OBJECTID: Integer (10.0)
TAXLOT: String (80.0)
TOWNSHIP: String (80.0)
RANGE: String (80.0)
SECTION: String (80.0)
QUARTER: String (80.0)
SIXTEENTH: String (80.0)
PARCEL: String (80.0)
MAPSUP: String (80.0)
MAPNUMBER: String (80.0)
Shape_Leng: Real (24.15)
Shape_Area: Real (24.15)
Address: String (80.0)
House_Numb: String (80.0)
Direction: String (80.0)
Street_Nam: String (80.0)
Street_Typ: String (80.0)
Unit_Numbe: String (80.0)
City: String (80.0)
State: String (80.0)
Zip: String (80.0)
Subdiv_Cod: String (80.0)
Subdivisio: String (136.0)
Block: String (80.0)
Lot: String (80.0)
MA: String (80.0)
SA: String (80.0)
Percent_Go: String (80.0)
LegalLot: String (80.0)
UGB: String (80.0)
FirePatrol: String (80.0)
NH: String (80.0)
```

We only need to join three fields to our buildings shapefile: `House_Numb`, `Street_Nam` and `Street_Typ`. <!-- Do we need unit number? -->

And now the spatial join to attach those fields to all of our buildings using the [ST_Contains query](http://postgis.net/docs/manual-1.4/ST_Contains.html):

<!-- Crap, did I make sure these were in the same coordinate system? Needs to be geographic. -->

```
ogr2ogr -f "ESRI Shapefile" data_processing/buildings_height_addressed.shp data_processing/building_el_join.shp -dialect sqlite -sql "SELECT b.Geometry, b.id, t.House_Numb, t.Street_Nam, t.Street_Typ, b.height FROM building_el_join b, 'data_processing/taxlots_addresses_joined.shp'.taxlots_addresses_joined t WHERE ST_Contains(t.Geometry, b.Geometry)"
```

[ST_Contains docs](http://postgis.net/docs/manual-1.4/ST_Contains.html)

<!--
#### PDAL fail
In PDAL, each of these operations is called a "stage". We'll be creating a single operation that will process each LAZ file into two DEMs: One bare earth model **Digital Terrain Model (DTM)** and one **Digital Surface Model (DSM)**, which contains everything on the surface, including buildings. These
will give us much higher resolution DEMs than are available from DOGAMI, so when we later do our zonal statistics, we'll get more accurate information. We're making both a DTM and a DSM so that we can have both available when making visual comparisons in JOSM during our OSM import.

First, you need to [get started with PDAL](http://www.pdal.io/quickstart.html#install-docker). Feel free to download and build PDAL from source, but I recommend using Docker, and the instructions here will assume you're using that.

Let's take a look at our first file:

_**Note:** In this command, the `-v` flag and the paths that follow are linking my local folder to a virtual folder within the Docker container called `data`. Your paths will be different. [Read here](http://www.pdal.io/quickstart.html#enable-docker-access-to-your-machine) for a quick intro to how this works._

```
docker run -v /Users/username/Github/bend_buildings:/data pdal/pdal:1.4 pdal info /data/data_processing/raw_lidar/20100528_43121h2101.laz
```

You should get back a summary of the contents of that file, including stats on all [dimensions](http://www.pdal.io/dimensions.html). -->
