var https = require('https');
var fs = require('fs');
var _ = require('lodash');
var download = require('download');

fs.readFile('data/tile_index_subset.geojson','utf8', function(err, data){
	if (err) { console.log(err)};
 	var geojson = JSON.parse(data);
	var files = _.map(geojson, 'properties.url');
	var names = _.map(geojson, 'properties.name');
	Promise.all(files.map(function(x,i){ download(x, 'data_processing/lidar/raw/' + geojson[i].properties.name )})).then(function() {
   		console.log('files downloaded!');
	});
});
