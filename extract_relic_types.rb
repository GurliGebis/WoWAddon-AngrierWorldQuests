#!/usr/bin/env ruby
require 'open-uri'
require 'json'

relic_ids = [ 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 ]
relics = {}

relic_ids.each do |relic_id|
	url = "http://www.wowhead.com/items=3.-#{relic_id}"
	page = open(url).read
	if m = /^var listviewitems = (.*);$/.match(page)
		data = m[1]
		data.gsub! /firstseenpatch:/, '"firstseenpatch":'
		list = JSON.parse( data )
		list.each do |item|
			relics[ item['id'] ] = relic_id
		end
	end
end

print "{", relics.collect{|k,v| "[#{k}]=#{v}"}.join(","), "}\n"
