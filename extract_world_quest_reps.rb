#!/usr/bin/env ruby
require 'nokogiri'
require 'open-uri'
require 'json'

url = 'https://www.wowhead.com/quests/type:118:129:115:116:131:137:111:123:122:112:110:114:130:119:126:125:117:142:139:146:145:144:151:120:113:136:135:124:121:152:109?filter=35;8;0'

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
