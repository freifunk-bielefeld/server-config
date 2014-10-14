#!/usr/bin/env python3

'''
Convert data received from alfred to
a format accepted by ffmap-d3 format.

License: GPL-3.0
Author: Freifunk Bielefeld
'''

import os
import sys
import time
import datetime
import re
import json
import argparse
import subprocess


'''
List of firmware version that are not legacy.
None will set legacy always to false.
'''
valid_firmwares = [None, "0.3"]


'''
Typical call:

./build_ffmap.py -m maps.txt -a aliases.json > nodes.json

The output is for ffmap-d3.

#### Maps Data File #####

The maps file (-m) contains the output from alfred.
Each line has one entry containing a MAC and a string value:
{ "b2:48:7a:f6:85:76", "{ \"links\" : [{ \"smac\" : \"b0:48:7a:f6:85:76\", \"dmac\" : \"8c:21:0a:d8:af:2b\", \"qual\" : 251 }, { \"smac\" : \"2a:88:01:80:6b:93\", \"dmac\" : \"ee:51:43:05:1f:ef\", \"qual\" : 255 }], \"clientcount\" : 2}\x0a" },

The data that was put into alfred by a node looks like this:
{
	"name" : "foobar",
	"firmware" : "ffbi-0.3",
	"geo" : "52.02513078 8.55887",
	"links" : [
		{ "smac" : "b0:48:7a:f6:85:76", "dmac" : "8c:21:0a:d8:af:2b", "qual" : 251 }, 
		{ "smac" : "2a:88:01:80:6b:93", "dmac" : "ee:51:43:05:1f:ef", "qual" : 255 }
	],
	"clientcount" : 2
}

Each link in "links" consists of a source MAC ("smac") and a destination MAC ("dmac") addresse.
"qual" refers to link quality (0-255). A node may have several network devices,
resulting in mutliple MACs that belong to one node.
"clientcount" is the number of connected (non-batman) clients/nodes.
The number is idependent of the "links" entries.

Note:
 - All entries are optional, except for the "smac" and "dmac" in each link.
 - The data may be passed through gzip before it is passed to alfred:
    echo "hello" | gzip | alfred -s 64

#### Aliases Data File #####

The aliases file (-a) contains additional data about nodes,
like names, GPS coordinates and information if the node
is an uplink node ("vpn" : true).

{
	"02:16:3c:58:d0:b5" : {
		"name" : "vpn1",
		"vpn" : "true",
		"gateway" : "true",
	},
	"ee:11:43:15:1f:ef" : {
		"name" : "Shadow"
	},
	"12:fe:ed:7e:86:00" : {
		"name" : "Cool Node",
		"geo" : "52.02513078 8.55887"
	}
}

The identifier MAC can be any MAC used by the node
as part of the "smac".
"vpn" : true forces every connection to be displayed as uplink.
"gateway" : true displays a node as gateway.

Note:
 - All entries are optional and will overwrite values from maps.

#### Services Data File #####

The services file is similar to the maps data file as the output comes from Alfred.
A formatted value may look like this:
{
	"link" : "http://10.20.30.40/",
	"label" : "My Public Gateway"
}

This is useful to announce services. Currently limited to one entry per router.
'''

link_re = re.compile('^[\w\.\:\[\]\(\)\/ ]{3,60}$')
label_re = re.compile('^[\w\.\:\[\]\(\)\/ ]{3,30}$')
mac_re = re.compile("^([0-9a-f]{2}:){5}[0-9a-f]{2}$")
geo_re = re.compile("^\d{1,3}\.\d+ \d{1,3}\.\d+$")
strings_re = re.compile(r'(?x)(?<!\\)"(.*?)(?<!\\)"')

def isMAC(mac):
	if isinstance(mac, str) and mac_re.match(mac):
		return True
	else:
		return False

def isGeo(geo):
	if isinstance(geo, str) and geo_re.match(geo):
		return True
	else:
		return False

def parseStrings(line):
	m = strings_re.findall(line)
	if m:
		return m
	else:
		return []

def isLink(link):
	if isinstance(link, str) and link_re.match(link):
		return True
	else:
		return False

def isLabel(label):
	if isinstance(label, str) and label_re.match(label):
		return True
	else:
		return False

'''
Convert between locally administered and globally administered MAC address
'''
def flip_mac(mac):
	return "{:02x}{}".format(int(mac[0:2], 16) ^ 2, mac[2:])

'''
Read and validate aliases file
'''
def readAliases(filename):
	aliases = None
	
	if not filename:
		return {}
	
	with open(filename) as f:
		aliases = json.load(f)

	#start validation
	if not isinstance(aliases, dict):
		raise Exception(
			"Invalid type for aliases."
		)
	
	def validateAliasesEntry(key, value):
		if key == "name":
			if not isinstance(value, str):
				raise Exception(
					"Entry {}. Invalid type for name.".format(mac)
				)
			if len(key) > 30:
				raise Exception(
					"Entry {}. Name too long.".format(mac)
				)
		elif key == "vpn":
			if not isinstance(value, bool):
				raise Exception(
					"Entry {}. Invalid type for vpn.".format(mac)
				)
		elif key == "gateway":
			if not isinstance(value, bool):
				raise Exception(
					"Entry {}. Invalid type for gateway.".format(mac)
				)
		elif key == "geo":
			if not isinstance(value, str):
				raise Exception(
					"Entry {}. Invalid type for geo.".format(mac)
				)
			if not isGeo(value):
				raise Exception(
					"Entry {}. Invalid geo format: {}".format(mac, value)
				)
		else:
			raise Exception(
				"Entry {}. Unexpected key: {}".format(mac, key)
			)

	for key, value in aliases.items():
		if not isMAC(key):
			raise Exception(
				"Invalid MAC address: {}".format(key)
			)

		if not isinstance(value, dict):
			raise Exception(
				"Invalid value type for {}".format(key)
			)

		for k, v in value.items():
			validateAliasesEntry(k, v)

	return aliases

def readMaps(filename):

	if not filename:
		return {}

	def validateMapLink(sender_mac, link):
		if not isinstance(link, dict):
			raise Exception(
				"Map entry {}. Invalid value type for links element.".format(sender_mac)
			)

		if not ("smac" in link and "dmac" in link):
			raise Exception(
				"Map entry {}. \"smac\" and \"dmac\" missing in links element.".format(sender_mac)
			)

		for key, value in link.items():
			if key == "smac" or key == "dmac":
				if not isMAC(value):
					raise Exception(
						"Map entry {}. Invalid format for link MAC: {}".format(sender_mac, value)
					)
			elif key == "qual":
				if not isinstance(value, int):
					raise Exception(
						"Map Entry {}. Invalid format for link quality: {}".format(sender_mac, value)
					)
	
				if value < 0 or value > 255:
					raise Exception(
						"Map Entry {}. Invalid range for link quality: {}".format(sender_mac, value)
					)
			elif key == "type":
				if not value in [None, "vpn"]:
					raise Exception(
						"Map Entry {}. Invalid value for link type: {}".format(sender_mac, value)
					)
			else:
				raise Exception(
					"Map entry {}. Unknown key in links: {}".format(sender_mac, ekey)
				)

	def validateMapEntry(sender_mac, json_value):
		if not isinstance(json_value, dict):
			raise Exception(
				"Map entry {}. Invalid value type.".format(sender_mac)
			)

		for key, value in json_value.items():
			if key == "geo":
				if not isGeo(value):
					raise Exception(
						"Map Entry {}. Invalid format for geo: {}".format(sender_mac, value)
					)
			elif key == "firmware":
				if not isinstance(value, str) or len(value) > 32:
					raise Exception(
						"Map entry {}. Invalid value type for firmware.".format(sender_mac)
					)
			elif key == "name":
				if not isinstance(value, str) or len(value) > 32:
					raise Exception(
						"Map entry {}. Invalid value type for name.".format(sender_mac)
					)
			elif key == "links":
				if not isinstance(value, list):
					raise Exception(
						"Map entry {}. Invalid value type for links.".format(sender_mac)
					)

				for link in value:
					validateMapLink(sender_mac, link)
			elif key == "clientcount":
				if not isinstance(value, int):
					raise Exception(
						"Map Entry {}. Invalid type for clientcount: {}".format(sender_mac, value)
					)

				if value < 0 or value > 255:
					raise Exception(
						"Map Entry {}. Invalid range for clientcount: {}".format(sender_mac, value)
					)
			else:
				raise Exception(
					"Map entry {}. Unknown key: {}".format(sender_mac, key)
				)

	maps = {}
	with open(filename) as f:
		for line in f.readlines():
			strings = parseStrings(line)
			if len(strings) == 2:
				try:
					node_mac = bytes(strings[0], 'utf-8').decode("unicode_escape")
					node_value = bytes(strings[1], 'utf-8').decode("unicode_escape")

					#data might be from gzip, let us try that
					if strings[1].endswith("\\x00"):
						proc = subprocess.Popen(['gunzip'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
						node_value = proc.communicate(node_value.encode('latin-1'))[0].decode("utf-8")

					node_value = json.loads(node_value)
					validateMapEntry(node_mac, node_value)
					maps[node_mac] = node_value

				except Exception as e:
					sys.stderr.write(str(e)+"\n")

	#pretty print json for debuging
	#print(json.dumps(maps, indent=4, sort_keys=True))

	return maps

def readServices(filename):

	if not filename:
		return {}

	def validateServiceEntry(sender_mac, json_value):
		if not isinstance(json_value, dict):
			raise Exception(
				"Service entry {}. Invalid value type.".format(sender_mac)
			)

		if not "link" in json_value:
			raise Exception(
				"Service entry {}. Addr not found.".format(sender_mac)
			)

		if not "label" in json_value:
			raise Exception(
				"Service entry {}. type not found.".format(sender_mac)
			)

		if not isLink(json_value["link"]):
			raise Exception(
				"Service entry {}. Invalid link format: {}".format(sender_mac, json_value["link"])
			)

		if not isLabel(json_value["label"]):
			raise Exception(
				"Service entry {}. Invalid label format: {}".format(sender_mac, json_value["label"])
			)

	services = {}
	with open(filename) as f:
		for line in f.readlines():
			strings = parseStrings(line)
			if len(strings) == 2:
				node_mac = bytes(strings[0], 'utf-8').decode("unicode_escape")
				node_value = bytes(strings[1], 'utf-8').decode("unicode_escape")

				#data might be from gzip, let us try that
				if strings[1].endswith("\\x00"):
					proc = subprocess.Popen(['gunzip'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
					node_value = proc.communicate(node_value.encode('latin-1'))[0].decode("utf-8")

				node_value = json.loads(node_value)
				try:
					validateServiceEntry(node_mac, node_value)
					services[node_mac] = node_value
				except Exception as e:
					sys.stderr.write(str(e)+"\n")

	return services

def main():
	parser = argparse.ArgumentParser()

	parser.add_argument('-a', '--aliases',
		help='read aliases from FILE')

	parser.add_argument('-s', '--services', 
		help='read services from FILE')

	parser.add_argument('-m', '--maps',
		help='read maps from FILE')

	args = parser.parse_args()
	if not args.maps:
		sys.stderr.write(
			"{}: Input file for --maps expected.\n".format(parser.prog)
		)
		return 1

	if args.maps and not os.path.isfile(args.maps):
		sys.stderr.write(
			"{}: File does not exist: {}\n".format(parser.prog, args.maps)
		)
		return 1

	if args.aliases and not os.path.isfile(args.aliases):
		sys.stderr.write(
			"{}: File does not exist: {}\n".format(parser.prog, args.aliases)
		)
		return 1

	if args.services and not os.path.isfile(args.services):
		sys.stderr.write(
			"{}: File does not exist: {}\n".format(parser.prog, args.services)
		)
		return 1

	#update node using the update data
	#no new keys will be introduced
	def mergeNodes(node1, node2):
		for key, value in node1.items():
			if not key in node2:
				sys.stderr.write(
					"Key expected to be present in both: {}\n".format(key)
				)
				continue

			new_value = node2[key]
			if key == "flags":
				for flag_key, flag_value in value.items():
					if not flag_key in new_value:
						sys.stderr.write(
							"Flag expected to be present in both: {}\n".format(flag_key)
						)
						continue
					alt_flag_value = new_value[flag_key]
					
					if not flag_value and alt_flag_value:
						value[flag_key] = True
			elif key == "macs":
				if len(value):
					node1["macs"] = node1["macs"] + " " + value
			elif key == "links":
				if len(value):
					node1["links"].extend(value)
			elif key == "name":
				if new_value and not isMAC(new_value):
					node1["name"] = new_value
			elif key == "geo":
				if new_value:
					node1["geo"] = new_value
			elif key == "clientcount":
				node1["clientcount"] += new_value
			elif key == "firmware":
				if new_value:
					node1["firmware"] = new_value
			elif key == "id":
				pass
			else:
				sys.stderr.write("Ingnored unknown key: {}\n".format(key))
	
	#map data from nodes via alfred
	maps = readMaps(args.maps)

	#locally stored additional data
	aliases = readAliases(args.aliases)

	#gateway data from nodes via alfred
	services = readServices(args.services)

	#<macs> => <node>
	nodes = {}
	
	def addNode(mac, node):
		old_node = nodes.get(mac, None)
		if old_node:
			if old_node == node:
				pass
			else:
				mergeNodes(old_node, node)
		else:
			nodes[mac] = node

	'''
	Add nodes we got from via alfred
	'''
	for mac, data in maps.items():
		firmware = data.get("firmware")
		name = data.get("name", mac)
		geo = data.get("geo")
		clientcount = data.get("clientcount", 0)

		if geo:
			geo = geo.split()

		macs = [ mac ]
		for link in data.get("links", []):
			macs.append(link["smac"])

		node = {
			'id': mac,
			'name': name,
			'geo': geo,
			'macs' : ' '.join(macs),
			'links' : data.get("links", []),
			'firmware': firmware,
			'clientcount' : clientcount,
			'flags': {"legacy": False, "gateway": False, "online": True}
		}

		'''add node under all known MACs'''
		addNode(flip_mac(mac), node)
		for smac in macs:
			addNode(smac, node)

	'''
	Add nodes from aliases database
	'''
	for mac, data in aliases.items():
		name = data.get("name", mac)
		geo = data.get("geo")
		gateway = data.get("gateway", False)

		if geo:
			geo = geo.split()

		addNode(mac, {
			'id': mac,
			'name': name,
			'geo': geo,
			'macs' : mac,
			'links' : [],
			'firmware': None,
			'clientcount' : 0,
			'flags': {"legacy": False, "gateway": gateway, "online": False}
		})

	'''
	Set gateway flag
	'''
	for mac, data in services.items():
		if mac in nodes and data["type"] == "gateway":
			nodes[mac]["flags"]["gateway"] = True

	'''
	Create a unique list of nodes by "id".
	'''
	nodes_list = list({v['id']:v for v in nodes.values()}.values())

	'''
	Add "index" and set "legacy".
	'''
	for idx, node in enumerate(nodes_list):
		node["index"] = idx
		
		if not (node.get("firmware") in valid_firmwares):
			node["flags"]["legacy"] = True

	links_list = []
	done_links = set()
	for node1 in nodes_list:
		for link1 in node1["links"]:
			smac1 = link1["smac"]
			dmac1 = link1["dmac"]
			qual1 = link1.get("qual", 1)
			type1 = link1.get("type", None)

			#prevent the same link from being listed twice 
			if (smac1 + dmac1) in done_links:
				continue
			
			done_links.add(dmac1+ smac1)
			done_links.add(smac1+dmac1)
			
			node2 = nodes.get(dmac1, None)
			if not node2:
				sys.stderr.write(
					"Warning: Cannot find node {} referenced by {}.\n".format(dmac1, smac1)
				)
				continue

			#check other direction
			found = False
			for link2 in node2["links"]:
				smac2 = link2["smac"]
				dmac2 = link2["dmac"]
				qual2 = link2.get("qual", 1)
				type2 = link2.get("type", None)
				
				#check if we have found the
				#same link from both sides
				if not (smac1 == dmac2 and dmac1 == smac2):
					continue

				found = True
				type = None
				quality = "{:.3f}, {:.3f}".format(
					255.0/max([qual1, 1]),
					255.0/max([qual2, 1]),
				)

				#display as uplink if any side of the link is marked as vpn
				for m in (node1["macs"] + node2["macs"]).split():
					if m in aliases and aliases[m].get("vpn", False):
						type = "vpn"

				links_list.append({
					"id": "{}-{}".format(smac1, smac2),
					"source": node1["index"],
					"target": node2["index"],
					"quality": quality,
					"type": type
				})

				break

			if not found:
				sys.stderr.write(
					"Warning: Unidirectional link found {} => {}.\n".format(smac1, dmac1)
				)

	'''
	Remove some temporary entries not intended for output.
	'''
	for node in nodes_list:
		del node["links"]
		del node["index"]
		del node["macs"]

	now = datetime.datetime.utcnow().replace(microsecond=0)

	output = {}
	output['nodes'] = nodes_list
	output['links'] = links_list
	output['meta'] = { 'timestamp': now.isoformat() }

	'''Print results to console'''
	print(json.dumps(output))

	return 0


if __name__ == '__main__':
	main()
