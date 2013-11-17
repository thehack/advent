var request = require('request');
var fs = require('fs');
var cheerio = require('cheerio');
var level = require('level')
var db = level('./test3')

// return a encoded url for verse lookup
var encodeUrl = function(verseName) {
	var verse = verseName.replace(" ", "%20")
	return "http://www.biblegateway.com/passage/?search=" + verse + "&version=NIV"
}

var verses = [ 'Isaiah 40:1-5',
  'Isaiah 40:9-11',
  'Genesis 3:8-15',
  'Psalm 89:1-4',
  'Isaiah11:1-10',
  'Micah 5:2-4',
  'Malachi 3:1-6',
  'John 1:1-8',
  'John 1:9-18',
  'Mark 1:1-3',
  'Luke 1:5-13',
  'Luke 1:14-17',
  'Luke 1:18-25',
  'Luke 1:39-45',
  'Luke 1:46-56',
  'Luke 1:57-66',
  'Luke 1:67-80',
  'Isaiah 7:10-14',
  'Luke 1:26-35',
  'Isaiah 9:2-7',
  'Matthew 1:18-25',
  'Luke 2:1-20',
  'Matthew 2:1-12',
  'Luke 2:21-35' ]

verses.forEach(function(verse, index){
	request(encodeUrl(verse), function (error, response, body) {
  		if (!error && response.statusCode == 200) {
			var $ = cheerio.load(body);
			var lines = $('span.text').text()
			// delete first number and space 
			lines = lines.replace(/^\d+\s/, "");
			// replace other numbers with hard returns
			lines = lines.replace(/\d+/g, "\n");
			//cross-references
			lines = lines.replace(/\[\D\]/g, "");
			db.put(String(index), verse + "|" + lines)
  		}
			else {
			console.log(err)
			}
	});
})



