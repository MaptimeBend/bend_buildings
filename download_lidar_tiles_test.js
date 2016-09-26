// Dependencies
var fs = require('fs');
var url = require('url');
var https = require('https');
var exec = require('child_process').exec;
var spawn = require('child_process').spawn;
var _ = require('lodash');

fs.readFile('data/tile_index_subset.geojson', function(err, data){
	if (err) throw err;
	var geojson = JSON.parse(data);
	// var file_list = _.map(geojson.features, 'properties.url');
	// console.log(file_list);
	var DOWNLOAD_DIR = 'data_processing/lidar/raw/';
	//
	// Function to download file using curl
	var download_file_curl = function(file_url) {
		// console.log(file_url);
		file_url = file_url.trim();
		// extract the file name
		var file_name = url.parse(file_url).pathname.split('/').pop();
		// create an instance of writable stream
		var file = fs.createWriteStream(DOWNLOAD_DIR + file_name);
		// execute curl using child_process' spawn function
		var curl = spawn('curl', [file_url]);
		// add a 'data' event listener for the spawn instance
		curl.stdout.on('data', function(data) { file.write(data); });
		// add an 'end' event listener to close the writeable stream
		curl.stdout.on('end', function(data) {
			file.end();
			console.log(file_name + ' downloaded to ' + DOWNLOAD_DIR);
		});
		// when the spawn child process exits, check if there were any errors and close the writeable stream
		curl.on('exit', function(code) {
			if (code != 0) {
				console.log('Failed: ' + code);
			}
		});
	};

	_.forEach(geojson.features, function(feature){
		// console.log(feature.properties.url)

		// App variables
		var file_url = feature.properties.url.toString();

		download_file_curl(file_url);
	});

});
