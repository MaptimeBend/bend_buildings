# Processing instructions to create Bend buildings OSM file from public data

## Getting started

Clone this repo. You'll find `README.md`, a `/data` directory, the `license.txt` file that contains the City of Bend release to use their data, a `demo` folder, which contains a web map that displays the latest dataset and a `final_osm` folder, which contains the final OSM file and other accompanying data produced using these instructions. While the `final_osm` folder should contain the information needed, this tutorial is provided as documentation for how the final files were produced and can be reproduced. No black boxes.

## Requirements:

- WGET
- GDAL
- PDAL (I used the [Docker container](http://www.pdal.io/quickstart.html), which requires [Docker](https://www.docker.com/))

I'll go into each of the above as they come up.

I used macOS when writing this tutorial, but most of the instructions should work from any command line.

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

Now lets make that new shapefile:

```
ogr2ogr data_processing/building_footprints.shp data/building_footprints2004_intlfeet.shp -sql "SELECT CAST(elevation AS numeric(10,3)) AS orig_el_ft FROM building_footprints2004_intlfeet" -progress -overwrite
```

Here's what's happening in that command (I won't break down all of them, just this one since it's kind of a beast):

- `ogr2ogr` This is the GDAL tool that transforms data.
- `data_processing/building_footprints.shp data/building_footprints2004_intlfeet.shp` ogr2ogr accepts output.shp input.shp as arguments.
- `-sql` This is a flag that accepts a string of SQL. In this case, we're selecting the `elevation` field from our input and casting it as a numeric value with a width of 10 and a precision of 3, then names it as `orig_el_ft` (original elevation in feet)
- `-progress` Shows the progress in the terminal, not required
- `-overwrite` Overwrites the output file if it already exists, not required but nice if you're executing a command multiple

Now we have a fresh shapefile with just the original elevation in feet for each building footprint.

## Adding building heights

Bend has pretty complete LIDAR coverage from 2011 via [DOGAMI](http://www.oregongeology.org/sub/lidardataviewer/index.htm). LIDAR is a way to collect a dense point cloud file that can be used to extract meaningful information about landscapes at a very high resolution. We'll use the raw LIDAR files (.las) to create high-resolution [DSM and DTM](https://en.wikipedia.org/wiki/Digital_elevation_model) images that we can use to extract elevations and building heights. We'll then create tiled versions of those to use during OSM import sessions as a heads-up comparison tool.

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

1021 features! That's a lot of LIDAR data, and we only need a few of them. And look, there's a URL field that points directly at the `.laz` files we need. What we need to do is figure out which of those `.laz` files we need, and then download and process each one.

To do that, we'll start by using `ogr2ogr` to clip the LIDAR `tile_index.shp` file using the `building_footprints.shp` file. But first, we'll need to make sure they're in the same coordinate system.

_tk_
