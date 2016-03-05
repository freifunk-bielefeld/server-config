#!/usr/bin/env python3
'''
Convert data received from alfred (ffbi format) to a format accepted by meshviewer or ffmap-d3

Typical call::

    alfred -r 64 > maps.txt
    ./map-backend.py -m maps.txt  --meshviewer-nodes nodes.json --meshviewer-graph graph.json

License: CC0 1.0
Author: Moritz Warning
Author: Julian Rueth (julian.rueth@fsfe.org)
'''

import json, jsonschema
import sys
import zlib
import re
import datetime
import os
import pickle

if sys.version_info[0] < 3:
    raise Exception("map-backend.py must be executed with Python 3.")

from pprint import pprint, pformat

now_timestamp = datetime.datetime.utcnow().replace(microsecond=0)

class AlfredParser:
    r'''
    A class providing static methods to parse and validate data reported by
    nodes via alfred.
    '''
    MAC_RE = "^([0-9a-f]{2}:){5}[0-9a-f]{2}$"
    GEO_RE = "^\d{1,3}\.\d{1,8} {1,3}\d{1,3}\.\d{1,8}$"
    MAC_SCHEMA = { "type": "string", "pattern": MAC_RE }
    ALFRED_NODE_SCHEMA = {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "geo": { "type": "string", "pattern": GEO_RE }, #deprecated in favor of longitude/latitude
            "name": { "type": "string", "maxLength": 32 },
            "contact": { "type": "string", "maxLength": 32 },
            "firmware": { "type": "string", "maxLength": 32 },
            "community": { "type": "string", "maxLength": 32 },

            'longitude' : { "type": "number" },
            'latitude' : { "type": "number" },
            'model': { "type": "string", "maxLength": 32 },
            'uptime': { "type": "number" },
            'loadavg': { "type": "number" },
            'rootfs_usage' : { "type": "number" },
            'memory_usage' : { "type": "number" },
            'addresses' :  {"type": "array", "items": { "type": "string" } },

            "clientcount": { "type": "integer", "minimum": 0, "maximum": 255 },
            "gateway": { "type": "boolean" },
            "vpn": { "type": "boolean" },
            "links": {
                "type": "array",
                "items": { "$ref": "#/definitions/link" }
            }
        },
        "definitions": {
            "MAC": MAC_SCHEMA,
            "link": {
                "type": "object",
                "properties": {
                    "smac": { "$ref": "#/definitions/MAC" },
                    "dmac": { "$ref": "#/definitions/MAC" },
                    "qual": { "type": "integer", "minimum": 0, "maximum": 255 },
                    "type": { "enum": [ "vpn" ] },
                },
                "required": ["smac", "dmac"],
                "additionalProperties": False
            }
        }
    }

    ALIASES_NODE_SCHEMA = {
        "type": "object",
        "additionalProperties": False,
        "mac" : MAC_SCHEMA,
        "properties": {
            "geo": { "type": "string", "pattern": GEO_RE }, #deprecated in favor of longitude/latitude
            'latitude' : { "type": "number" },
            'longitude' : { "type": "number" },
            'model': { "type": "string", "maxLength": 32 },
            'uptime': { "type": "number" },

            "name": { "type": "string", "maxLength": 32 },
            "contact": { "type": "string", "maxLength": 64 },
            "firmware": { "type": "string", "maxLength": 32 },
            "community": { "type": "string", "maxLength": 32 },
            "clientcount": { "type": "integer", "minimum": 0, "maximum": 255 },
            
            "gateway": { "type": "boolean" },
            "vpn": { "type": "boolean" },
            "type" : { "enum": [ "node", "gateway" ] },
            "force": { "type": "boolean" }
        }
    }

    ALIASES_SCHEMA = {
        "type": "object",
        "patternProperties": {
            MAC_RE : {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "geo": { "type": "array", "items": [{'type' : 'number'}, {'type' : 'number'}]}, #deprecated in favor of longitude/latitude
                    'latitude' : { "type": "number" },
                    'longitude' : { "type": "number" },
                    'model': { "type": "string", "maxLength": 32 },
                    'uptime': { "type": "number" },
                    'loadavg': { "type": "number" },
                    
                    "name": { "type": "string", "maxLength": 32 },
                    "contact": { "type": "string", "maxLength": 32 },
                    "firmware": { "type": "string", "maxLength": 32 },
                    "community": { "type": "string", "maxLength": 32 },
                    "clientcount": { "type": "integer", "minimum": 0, "maximum": 255 },
                    "gateway": { "type": "boolean" },
                    "vpn": { "type": "boolean" },
                    "force": { "type": "boolean" }
                }
            }
        }
    }

    @staticmethod
    def _parse_string(s):
        r'''
        Strip an escaped string which is enclosed in double quotes and
        unescape.
        '''
        if s[0] != '"' or s[-1] != '"':
            raise ValueError("malformatted string: {0:r}".format(s))
        return bytes(s[1:-1], 'ascii').decode('unicode-escape')

    @staticmethod
    def parse_line(item, nodes = {}, links = {}):
        r'''
        Parse and validate a line as returned by alfred.

        Such lines consist of a nodes MAC address and an escaped string of JSON
        encoded data. Note that most missing fields are populated with
        reasonable defaults.
        '''

        # parse the strange output produced by alfred { MAC, JSON },
        if item[-2:] != "}," or item[0] != "{":
            raise ValueError("malformatted line: {0}".format(item))
        mac, properties = item[1:-2].split(',',1)

        # the first part must be a valid MAC
        mac = AlfredParser._parse_string(mac.strip())
        jsonschema.validate(mac, AlfredParser.MAC_SCHEMA)

        # the second part must conform to ALFRED_NODE_SCHEMA
        properties = AlfredParser._parse_string(properties.strip())

        if "\x00" in properties:
            decompress = zlib.decompressobj(zlib.MAX_WBITS|32)
            # ignores any output beyond 64k (protection from zip bombs)
            properties = decompress.decompress(properties.encode('raw-unicode-escape'),64*1024).decode('utf-8')
        else:
            properties = properties.encode('latin-1').decode('utf8')

        properties = json.loads(properties)
        jsonschema.validate(properties, AlfredParser.ALFRED_NODE_SCHEMA)

        # set some defaults for unspecified fields
        #properties.setdefault('name', mac)
        if 'geo' in properties:
            geo = properties['geo'].split()
            properties['geo'] = [ float(geo[0]), float(geo[1]) ]
            properties['latitude'] = float(geo[0])
            properties['longitude'] = float(geo[1])

        properties.setdefault('gateway', False)
        properties.setdefault('vpn', False)
        properties.setdefault('links', [])
        node_links = properties['links']
        del properties['links']

        if mac in nodes:
            # update existing node
            node = nodes[mac]
            node.update_properties(properties, True)
            node.online = True
            node.lastseen = now_timestamp
        else:
            # create a new Node
            node = Node(mac, properties, True)
            nodes[mac] = node

        # add links and connect source mac to node
        for node_link in node_links:
            smac = node_link['smac']
            dmac = node_link['dmac']
            quality = node_link.get('qual', 0.) / 255.
            nodes[smac] = node
            links[(smac, dmac)] = Link(node, smac, dmac, quality)


class Node:
    r'''
    A node in the freifunk network, identified by its primary MAC.
    '''
    def __init__(self, mac, properties, online):
        self.mac = mac
        self.properties = properties

        if online:
            self.lastseen = now_timestamp
            self.firstseen = now_timestamp
        else:
            self.lastseen = None
            self.firstseen = None

        self.online = online
        self.index = None # the index of this node in the list produced for ffmap
        self.done = False

    def update_properties(self, properties, force = True):
        r'''
        Replace any properties with their respective values in ``properties``.
        '''
        if force:
            ''' merge/overwrite values '''
            self.properties.update(properties)
        else:
            ''' add new key/value pairs only if not already set '''
            for key, value in properties.items():
                if not key in self.properties:
                    if key == "force":
                        continue

                    if key == "name":
                        value = value+"*"

                    self.properties[key] = value

    def meshviewer(self):
        properties = self.properties

        name = properties.get('name', self.mac)
        contact = properties.get('contact', None)
        community = properties.get('community', None)
        firmware = properties.get('firmware', None)
        longitude = properties.get('longitude', None)
        latitude = properties.get('latitude', None)
        clientcount = properties.get('clientcount', 0)
        uptime = properties.get('uptime', None)
        loadavg = properties.get('loadavg', None)
        model = properties.get('model', None)
        rootfs_usage = properties.get('rootfs_usage', None)
        memory_usage = properties.get('memory_usage', None)
        addresses = properties.get('addresses', None)
        
        obj = {
            'statistics' : {},
            'nodeinfo' : {
                'network' : {
                    'mac': self.mac
                }
            }
        }

        if uptime:
            obj["statistics"]['uptime'] = uptime

        obj["statistics"]['clients'] = clientcount
        
        if loadavg:
            obj["statistics"]['loadavg'] = loadavg

        if rootfs_usage:
            obj["statistics"]['rootfs_usage'] = rootfs_usage

        if memory_usage:
            obj["statistics"]['memory_usage'] = memory_usage

        if addresses:
            obj["nodeinfo"]['network']['addresses'] = addresses

        obj['nodeinfo']['hostname'] = name
        obj['nodeinfo']['node_id'] = re.sub('[:]', '', self.mac)

        if contact:
            obj["nodeinfo"]["owner"] = { "contact" : contact }

        if longitude and latitude:
            obj['nodeinfo']['location'] = {
                "longitude": longitude,
                "latitude": latitude
            }

        if firmware:
            obj['nodeinfo']['software'] = {
                'firmware' : { "release" : firmware }
            }

        obj['nodeinfo']['system'] = {}
        if community:
            obj['nodeinfo']['system']["site_code"] = community

        if properties['gateway']:
            obj['nodeinfo']['system']["role"] = "gateway"
        else:
            obj['nodeinfo']['system']["role"] = "node"

        if model:
            obj['nodeinfo']['hardware'] = {
                "model" : model
            }

        obj['flags'] = {
            "online" : self.online,
            "gateway" : properties['gateway']
        }

        if self.firstseen:
            obj['firstseen'] = self.firstseen.isoformat()

        if self.lastseen:
            obj['lastseen'] = self.lastseen.isoformat()

        return obj

    def ffmap(self):
        r'''
        Render this node (without its links) to a dictionary in a format
        understood by ffmap.
        '''
        properties = self.properties
        name = properties.get('name', None)
        contact = properties.get('contact', None)
        community = properties.get('community', None)
        firmware = properties.get('firmware', None)
        latitude = properties.get('latitude', None)
        longitude = properties.get('longitude', None)
        clientcount = properties.get('clientcount', None)
        gateway = properties.get('gateway', False)
        uptime = properties.get('uptime', None)
        loadavg = properties.get('loadavg', None)
        rootfs_usage = properties.get('rootfs_usage', None)
        memory_usage = properties.get('memory_usage', None)
        model = properties.get('model', None)
        vpn = properties.get('vpn', False)

        obj = {
            'id': self.mac,
            'flags': {
                "gateway": gateway,
                "vpn": vpn,
                "online": self.online
            }
        }

        if self.firstseen:
            obj['firstseen'] = self.firstseen.isoformat()

        if self.lastseen:
            obj['lastseen'] = self.lastseen.isoformat()

        if name:
            obj['name'] = name

        if contact:
            obj['contact'] = contact

        if community:
            obj['community'] = community

        if firmware:
            obj['firmware'] = firmware

        if latitude and longitude:
            obj['geo'] = [latitude, longitude]

        if clientcount:
            obj['clientcount'] = clientcount

        if uptime:
            obj['uptime'] = uptime

        if loadavg:
            obj['loadavg'] = loadavg

        if model:
            obj['model'] = model

        if loadavg:
            obj['loadavg'] = loadavg

        if rootfs_usage:
            obj['rootfs_usage'] = rootfs_usage

        if memory_usage:
            obj['memory_usage'] = memory_usage

        return obj

    # a printable representation (which is missing the links)
    def __repr__(self): return r'Node({0!r}, {1!s}, online={2!r})'.format(self.mac, pformat(self.properties), self.online)


class Link:
    r'''
    A link between two nodes.

    A Link is associated to one :class:`Node`, the node which is the source of
    the link. It has attributes ``smac`` and ``dmac`` which are MACs of the
    interfaces which this link connects. (These are usually not the primary
    MACs of the nodes which this link connects, i.e., ``link.smac !=
    link.source.mac``.)

    Typically, links come in pairs. There is a symmetric link with ``smac`` and
    ``dmac`` interchanged. Once that symmetric link has been discovered, an
    attribute ``reverse`` holds a reference to the symmetric link.

    Additionally each link specifies a connection quality in the range `[0,1]`.
    '''
    def __init__(self, source, smac, dmac, quality):
        self.source = source
        self.smac = smac
        self.dmac = dmac
        self.quality = quality

        self.reverse = None
        self.done = False

    def meshviewer(self):
        r'''
        Render this link to a dictionary in a format understood by ffmap.
        '''
        if not self.reverse:
            raise ValueError("link must have 'reverse' set to render to ffmap")

        if self.source.index is None or self.reverse.source.index is None:
            raise ValueError("link's source and target must have their 'index' set to render to ffmap")

        return {
            'source': self.source.index,
            'target': self.reverse.source.index,
            "bidirect": True,
            'tq': float('{:.3f}'.format((1. / self.quality + 1. / self.reverse.quality) / 2.0)),
            'vpn': True if self.source.properties['vpn'] or self.reverse.source.properties['vpn'] else False
        }

    def ffmap(self):
        r'''
        Render this link to a dictionary in a format understood by ffmap.
        '''
        if not self.reverse:
            raise ValueError("link must have 'reverse' set to render to ffmap")

        if self.source.index is None or self.reverse.source.index is None:
            raise ValueError("link's source and target must have their 'index' set to render to ffmap")

        return {
            'id': '{}-{}'.format(self.smac,self.dmac),
            'source': self.source.index,
            'target': self.reverse.source.index,
            'quality': '{:.3f}, {:.3f}'.format(self.quality, self.reverse.quality),
            'vpn': True if self.source.properties['vpn'] or self.reverse.source.properties['vpn'] else False
        }

    # a printable representation
    def __repr__(self): return r'{0} (of {1}) -> {2} (of {3})'.format(self.smac, self.source.mac, self.dmac, self.reverse.source.mac if self.reverse else '?')


def render_meshviewer_nodes(nodes, links):
    for link in links.values():
        link.done = False

    for node in nodes.values():
        node.done = False

    all_nodes = {}
    for node in nodes.values():
        if node.done:
            continue
        node.done = True
        id = re.sub('[:]', '', node.mac)
        all_nodes[id] = node.meshviewer()

    return {
        'meta' : { 'timestamp': now_timestamp.isoformat() },
        'version' : 1,
        'nodes' : all_nodes
    }

def render_meshviewer_graph(nodes, links):
    for link in links.values():
        link.done = False

    for node in nodes.values():
        node.done = False

    #add mapping between map and node_id
    all_nodes = []
    index = 0
    for node in nodes.values():
        if node.done:
            continue

        node.index = index
        all_nodes.append({
            'node_id' : re.sub('[:]', '', node.mac),
            'id' : node.mac
        })
        index += 1
        node.done = False

    # a dictionary (smac,dmac)->link which is used to discover the reverse of each link
    all_links = []
    for link in links.values():
        if not link.done and link.reverse:
            all_links.append(link.meshviewer())
            link.done = True
            link.reverse.done = True

    return {
        'version' : 1,
        'batadv' : {
            'graph' : [],
            'nodes' : all_nodes,
            'multigraph' : False,
            'directed' : False,
            'links' : all_links
        }
    }

def render_ffmap(nodes, links):
    r'''
    Return a JSON representation of ``nodes`` which is understood by ffmap.
    '''
    for link in links.values():
        link.done = False

    for node in nodes.values():
        node.done = False

    index = 0
    all_nodes = []
    for node in nodes.values():
        if node.done:
            continue
        node.done = True
        node.index = index
        index += 1
        all_nodes.append(node.ffmap())
    
    # render a list of links
    all_links = []
    for link in links.values():
        if link.done:
            continue
        link.done = True
        if link.reverse:
            all_links.append(link.ffmap())
            link.reverse.done = True

    return {
        'meta' : { 'timestamp': now_timestamp.isoformat() },
        'nodes' : all_nodes,
        'links' :  all_links
   }

def loadNodes(path):
    nodes = {}
    with open(path, 'rb') as f:
        nodes = pickle.load(f)

    for node in nodes.values():
        #reset temporaies
        node.online = False
        node.index = None;

    return nodes

def saveNodes(path, nodes):
    with open(path, 'wb') as f:
        pickle.dump(nodes, f)

def removeOldNodes(nodes, delta):
    limit = now_timestamp - delta
    old_keys = []

    for key, node in nodes.items():
        if node.lastseen < limit:
            old_keys.append(key)

    count = 0
    for key in old_keys:
        del nodes[key]
        count += 1

    print("Removed {} old nodes".format(count))
    

# count unique node entries
def countNodes(nodes):
    for node in nodes.values():
        node.done = False

    count = 0
    for node in nodes.values():
        if node.done:
            continue;
        count += 1
        node.done = True
    return count

def isFile(path):
    return path and os.path.isfile(path)

def main():
    import argparse, sys, json

    parser = argparse.ArgumentParser('Convert data received from alfred to a format accepted by ffmap-d3')
    parser.add_argument('-a', '--aliases', help=r'a dictionary of overwrites to replace (offending) properties of some nodes')
    parser.add_argument('-m', '--maps', required=True, help=r'input file containing data collected by alfred')
    parser.add_argument('--ffmap-nodes',help=r'output nodes.json file for ffmap')
    parser.add_argument('--meshviewer-nodes', help=r'output nodes.json file for meshviewer')
    parser.add_argument('--meshviewer-graph', help=r'output graph.json file for meshviewer')
    parser.add_argument('--storage', default="nodes_backup.bin",help=r'store old data between calls e.g. to remember node lastseen values')
    parser.add_argument('-c', '--communities', nargs='+', help=r'Communities we want to filter for. Show all if none defined.')
    args = parser.parse_args()

    nodes = {}
    links = {}

    if isFile(args.storage):
        nodes = loadNodes(args.storage)
        print("Loaded {} nodes from {}".format(countNodes(nodes), args.storage))

    removeOldNodes(nodes, datetime.timedelta(days = 7))

    with open(args.maps, 'r') as maps:
        for line in maps.readlines():
            try:
                AlfredParser.parse_line(line.strip(), nodes, links)
            except:
                import traceback
                traceback.print_exc()
                continue

    if isFile(args.aliases):
        with open(args.aliases, 'r') as file:
            aliases = json.loads(file.read())
            jsonschema.validate(aliases, AlfredParser.ALIASES_SCHEMA)

            for mac, properties in aliases.items():
                node = nodes.get(mac, None);
                if node:
                    force = properties.get("force", False)
                    node.update_properties(properties, force)

    #filter out unknown communities
    for node in nodes.values():
        if args.communities and node.properties.get('community') not in args.communities:
            continue

    # find reverse node for each link
    for link in links.values():
        if link.reverse:
            continue

        reverse = links.get((link.dmac, link.smac), None)
        if not reverse:
            # commented because of too many error messages
            #sys.stderr.write("Link {0} -> {1} has only been reported by one of its ends.\n".format(link.smac,link.dmac))
            continue

        link.reverse = reverse
        link.reverse.reverse = link

    if args.meshviewer_nodes:
        with open(args.meshviewer_nodes, 'w') as file:
            nodes_json = render_meshviewer_nodes(nodes, links)
            file.write(json.dumps(nodes_json))

    if args.meshviewer_graph:
        with open(args.meshviewer_graph, 'w') as file:
            graph_json = render_meshviewer_graph(nodes, links)
            file.write(json.dumps(graph_json))

    if args.ffmap_nodes:
        with open(args.ffmap_nodes, 'w') as file:
            nodes_json = render_ffmap(nodes, links)
            file.write(json.dumps(nodes_json))

    if args.storage:
        saveNodes(args.storage, nodes)


if __name__ == '__main__':
    main()
