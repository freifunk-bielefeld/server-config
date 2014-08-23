#!/usr/bin/python3

import sys
import os
import json
import re
import subprocess

'''
This script sets the text values for fields labeled
"node_counter" and "client_counter" of a SVG file.
'''
def execute(args):
	p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
	out, err = p.communicate()
	return out

def main(argv):

	if len(argv) != 3:
		print("Usage: {} <json-file> <svg-file>".format(argv[0]))
		return 0

	json_path = argv[1]
	svg_path = argv[2]

	def readSVG(path):
		content = ""
		with open(path, 'r') as svg_file:
			content = svg_file.read()
		return content

	def writeSVG(path, content):
		with open(path, 'w') as svg_file:
			svg_file.write(content)

	def setSVGText(content, label_id, label_text):
		pattern = r'(.*?<text[^>]*?"'+label_id+'"[^>]*?>\s*<tspan[^>]*>)([^<>]*)(</tspan>.*)$'
		m = re.match(pattern, content, re.DOTALL)
		if m:
			return m.group(1) + label_text + m.group(3)
		else:
			return content

	json_content = ""	
	with open(json_path, 'r') as json_file:
		json_content = json_file.read()

	decoded = json.loads(json_content)
	node_counter = 0
	client_counter = 0
	gateway_counter = 0

	for element in decoded["nodes"]:
		gateway_flag = 

		if element["flags"].get("online", False):
			continue

		node_counter += 1
		client_counter += element.get("clientcount", 0)

		if element["flags"].get("gateway", False):
			gateway_counter += 1

	#FFBI fixup, since we have ghost clients for each node
	client_counter -= 2 * (node_counter) + gateway_counter

	#print("gatewway_counter: {}".format(gateway_counter))
	#print("client_counter: {}".format(client_counter))
	#print("node_counter: {}".format(node_counter))

	svg_content = readSVG(svg_path)
	svg_content = setSVGText(svg_content, "gateway_counter", str(gateway_counter))
	svg_content = setSVGText(svg_content, "node_counter", str(node_counter))
	svg_content = setSVGText(svg_content, "client_counter", str(client_counter))
	svg_content = setSVGText(svg_content, "date_updated", execute(["date", "+'%Y-%m-%d %T'"]))

	writeSVG(svg_path, svg_content)

if __name__ == '__main__':
	main(sys.argv)
