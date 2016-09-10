#!/usr/bin/env ruby
require 'nokogiri'
require 'open-uri'
require 'json'

url = 'http://www.wowhead.com/quests/legion/type:118:129:115:116:131:137:111:123:122:112:110:114:130:119:126:125:117:120:113:136:135:124:121:109'

page = open(url).read

out = {}
if m = /^new Listview\(\{template: 'quest', id: 'quests', data:(.*)\}\);$/.match(page)
	data = m[1]
	list = JSON.parse( data )
	item = list.first
	list.each do |item|
		if item['reprewards']
			out[ item['id'] ] = item['reprewards'].map{|i| i.first }
		end
	end
end

print "{", out.collect{|k,v| "[#{k}]=#{v.count==1 ? v.first : ('{'+v.join(",")+'}') }"}.join(","), "}\n"
