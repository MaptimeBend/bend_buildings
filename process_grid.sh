# This script will build a folder with about 10GB of 25cm grids

# Temp folder for LAZ files
echo "Creating temp folders for lidar data"
mkdir data_processing/temp

# Grab lidar tile index and unzip
# curl -O data_processing/tileindex.zip data https://coast.noaa.gov/htdata/lidar1_z/geoid12a/data/1452/tileindex.zip
# unzip data_processing/tileindex.zip -d data_processing

# Clip to extent of Bend buildings (acquiring this bounding box is skipped in this script)
# ogr2ogr -f "ESRI Shapefile" data_processing/tileindex_subset.shp data_processing/2010_OR_DOGAMI_Newberry_index.shp -clipsrc -121.192770 44.123710 -121.378524 43.993228

# Create a CSV of the URLs
# ogr2ogr -f "CSV" data_processing/lidar_urls.csv data_processing/tileindex_subset.shp -sql "SELECT url FROM tileindex_subset" -overwrite

# Adding an array manually. Eventually this should be created above

arr=(20100528_44121a4425 20100528_44121a4410 20100528_44121a4405 20100528_44121a4225 20100528_44121a4220 20100528_44121a4215 20100528_44121a3425 20100528_44121a3424 20100528_44121a3423 20100528_44121a3422 20100528_44121a3421 20100528_44121a3420 20100528_44121a3419 20100528_44121a3418 20100528_44121a3417 20100528_44121a3416 20100528_44121a3415 20100528_44121a3414 20100528_44121a3413 20100528_44121a3412 20100528_44121a3411 20100528_44121a3410 20100528_44121a3409 20100528_44121a3408 20100528_44121a3407 20100528_44121a3406 20100528_44121a3405 20100528_44121a3404 20100528_44121a3403 20100528_44121a3402 20100528_44121a3401 20100528_44121a3325 20100528_44121a3324 20100528_44121a3323 20100528_44121a3322 20100528_44121a3321 20100528_44121a3320 20100528_44121a3319 20100528_44121a3318 20100528_44121a3317 20100528_44121a3316 20100528_44121a3315 20100528_44121a3314 20100528_44121a3313 20100528_44121a3312 20100528_44121a3311 20100528_44121a3310 20100528_44121a3309 20100528_44121a3308 20100528_44121a3307 20100528_44121a3306 20100528_44121a3305 20100528_44121a3304 20100528_44121a3303 20100528_44121a3302 20100528_44121a3301 20100528_44121a3225 20100528_44121a3224 20100528_44121a3223 20100528_44121a3222 20100528_44121a3221 20100528_44121a3220 20100528_44121a3219 20100528_44121a3218 20100528_44121a3217 20100528_44121a3216 20100528_44121a3215 20100528_44121a3214 20100528_44121a3213 20100528_44121a3212 20100528_44121a3211 20100528_44121a3210 20100528_44121a3209 20100528_44121a3208 20100528_44121a3207 20100528_44121a3206 20100528_44121a3204 20100528_44121a3203 20100528_44121a3202 20100528_44121a3201 20100528_44121a3125 20100528_44121a3124 20100528_44121a3123 20100528_44121a3122 20100528_44121a3121 20100528_44121a3120 20100528_44121a3119 20100528_44121a3118 20100528_44121a3117 20100528_44121a3116 20100528_44121a3115 20100528_44121a3114 20100528_44121a3113 20100528_44121a3112 20100528_44121a3111 20100528_44121a3110 20100528_44121a3109 20100528_44121a2323 20100528_44121a2322 20100528_44121a2321 20100528_44121a2318 20100528_44121a2317 20100528_44121a2316 20100528_44121a2312 20100528_44121a2311 20100528_44121a2307 20100528_44121a2306 20100528_44121a2301 20100528_44121a2121 20100528_44121a2116 20100528_43121h4205 20100528_43121h3205 20100528_43121h3204 20100528_43121h3203 20100528_43121h3202 20100528_43121h3201 20100528_43121h3105 20100528_43121h3104 20100528_43121h3103 20100528_43121h3102 20100528_43121h3101 20100528_43121h2104 20100528_43121h2103 20100528_43121h2102 20100528_43121h2101)

mkdir data_processing/temp/height

# Loop through all of the lidar files we need
for i in ${arr[@]}
do
	# Download the file
	echo "Downloading $i"
	curl -o data_processing/temp/temp.laz https://coast.noaa.gov/htdata/lidar1_z/geoid12a/data/1452/$i.laz

	echo "Processing lidar"
	# Uncompress and reproject the lidar
	las2las -i data_processing/temp/temp.laz -o data_processing/temp/temp.las --t_srs http://spatialreference.org/ref/epsg/32127/ --a_srs http://spatialreference.org/ref/epsg/4269/ --scale 0.01 0.01 0.01
	# Create a 25cm bare earth grid
	echo "Creating bare earth grid"
	points2grid -i data_processing/temp/temp.las --resolution 0.25 --idw -o data_processing/temp/temparc --output_format arc --fill --exclude_class 1
	echo "Attempting to fill null values"
	gdal_fillnodata.py data_processing/temp/temparc.idw.asc data_processing/temp/bare_temp.geotiff -md 1000

	# Create a 25cm last returns grid
	echo "Creating first return grid"
	points2grid -i data_processing/temp/temp.las --resolution 0.25 --idw -o data_processing/temp/temparc2 --output_format arc --fill --first_return_only
	echo "Attempting to fill null values"
	gdal_fillnodata.py data_processing/temp/temparc2.idw.asc data_processing/temp/last_temp.geotiff

	# Create a feature height surface grid
	echo "Creating feature height surface grid"
	gdal_calc.py -A data_processing/temp/last_temp.geotiff -B data_processing/temp/bare_temp.geotiff --outfile=data_processing/temp/height/$i.geotiff --calc="A-B"
	gdal_fillnodata.py data_processing/temp/height/$i.geotiff data_processing/temp/height/$i.geotiff
	#

	echo "Removing temp files"
	rm data_processing/temp/temp.laz
	rm data_processing/temp/temp.las
	rm data_processing/temp/temparc.idw.asc
	rm data_processing/temp/temparc2.idw.asc
	rm data_processing/temp/bare_temp.geotiff
	rm data_processing/temp/last_temp.geotiff
done

# At this point you should have a folder full of 25cm geotiffs representing height above ground
