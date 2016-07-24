#!/usr/bin/env ruby
require 'nokogiri'
require 'open-uri'
require 'json'

url = 'http://www.wowhead.com/items/consumables?filter=224;1;0'

page = open(url).read

out = {}
if m = /^var listviewitems = (.*);$/.match(page)
	data = m[1]
	data.gsub! /firstseenpatch:/, '"firstseenpatch":'
	list = JSON.parse( data )
	list.each do |item|
		item_url = "http://www.wowhead.com/item=#{item['id']}&xml"
		item_doc = Nokogiri::XML open(item_url)

		item_tooltip = item_doc.css('htmlTooltip').first.content

		item_power = item_tooltip[/Grants (\d+) Artifact Power to your currently equipped Artifact\./, 1].to_i
		if item_power > 0
			out[ item['id'] ] = item_power
		end
	end
end

print "{", out.collect{|k,v| "[#{k}]=#{v}"}.join(","), "}\n"
