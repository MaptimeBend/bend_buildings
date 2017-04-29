# Bend Building Import Project

This repo acts as a workspace for doing a bulk import of the 2004 building footprints from the City of Bend. Inspired in part by the [excellent job done by the Los Angeles maptime folks](https://github.com/osmlab/labuildings).

![](buildings.png)

## Purpose

Currently only a handful of buildings are available in OpenStreetMap for Bend. While the city's dataset is 12 years old as of 2016, there are still 36,213 features in the dataset, most of which are probably still there. Although thousands of buildings will be missing, this will be a great start!

## Steps

[x] Acquire city data

[x] Create import [wiki page](https://wiki.openstreetmap.org/wiki/Bend_building_import)
 - The wiki page also needs to be maintained throughout the project

[x] Determine attributes to be imported (discuss in [this issue](https://github.com/MaptimeBend/bend_buildings/issues/1))

[x] Acquire any additional data needed

[x] Process data

[ ] Get "buy in" from OSM community

[ ] Prepare import: [OSM wiki page on imports](http://wiki.openstreetmap.org/wiki/Import/Guidelines)

[ ] Decide on how to divide import tasks

[ ] Execute import

## Building our dataset from scratch

Required packages:

- [gdal](http://www.gdal.org/)
- [liblas](https://www.liblas.org/)
- [postgres](https://www.postgresql.org/) w/ [postgis](http://postgis.net/)
- [rasterio](https://mapbox.github.io/rasterio/)
- [rasterstats](https://github.com/perrygeo/python-rasterstats)
- [points2grid](https://github.com/CRREL/points2grid/)

With the exception of points2grid, these packages can all be installed using python `pip`.

However, this tutorial recommends using a python virtual environment to keep everything tidy. The easiest way to do that is to install [anaconda](https://www.continuum.io/downloads) or [miniconda](https://conda.io/miniconda.html). These scripts were created using miniconda on MacOS. Commands could vary slightly for other systems, see the [documentation](https://conda.io/docs/).

Once either of those is installed, you should have access to the `conda` command line tool.

To create a new environment:

```
conda create --name python35 python=3
```

Now activate this environment:

```
source activate python35
```

Now install dependencies. This tutorial uses Homebrew and Conda to fetch everything. See individual package docs for other operating systems.

```
conda install gdal
brew install liblas --with-laszip
brew install postgres
brew install postgis
brew install points2grid
conda install rasterio
conda install rasterstats
```

Then clone this repo and `cd` into the main directory.

### Build database of buildings with addresses

This assumes that you have Postgres installed with a user named "postgres" and listening on the default port. See the script itself for annotated source.

```
sh process_addresses.sh
```

This should create a new database named `buildings` and add a table named `buildings`. Source data are our building footprint file and the latest taxlot and address information available from data.deschutes.gov.

### Create height grid from lidar data

This script will download the raw lidar files for Bend from NOAA and process them into a GeoTIFF with one band representing feature height above ground. See the script itself for annotated source. **WARNING:** This will probably take hours and result in a 10GB+ geotiff dataset. Feel free to tweak the resolution settings to speed up the process and reduce file sizes. The original script created a 25cm grid, but that is in all likelihood more resolution than is necessary.

```
sh process_grid.sh
```

### Extract building heights from height grid

This will use our building footprints table in postgres to extract the median value of the grid within each building polygon. It will append that info to the buildings table.

```
sh process_building_heights.sh
```

In addition, this script will export a GeoJSON file to the `demo` folder and an OSM file to the main directory. To view a demo of the data, `cd` to demo and start a web server.

## Additional info

Path to DOGAMI LiDAR:  ftp://coast.noaa.gov/pub/DigitalCoast/lidar1_z/geoid12a/data/1452/ or https://coast.noaa.gov/htdata/lidar1_z/geoid12a/data/1452/
