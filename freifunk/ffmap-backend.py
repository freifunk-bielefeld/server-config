#!/usr/bin/env python3
'''
Convert data received from alfred to a format accepted by ffmap-d3.

Typical call::

    alfred -r 64 > maps.txt
    ./ffmap-backend.py -m maps.txt -a aliases.json > nodes.json

.. note::

    To extend the list of fields which are reported by nodes, it is usually
    sufficient to adapt the ``ALFRED_NODE_SCHEMA`` and add some defaults in
    :meth:`AlfredParser.parse_node`.

    To change the output for ffmap, it is usually sufficient to adapt
    :meth:`Node.ffmap` and :meth:`Link.ffmap`.

License: CC0 1.0
Author: Moritz Warning
Author: Julian Rueth (julian.rueth@fsfe.org)
'''

import json, jsonschema
import sys

if sys.version_info[0] < 3:
    raise Exception("ffmap-backend.py must be executed with Python 3.")

from pprint import pprint, pformat

# list of firmware version that are not legacy.
RECENT_FIRMWARES = ["ffbi-0.4.3", "server", None]


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
            "geo": { "type": "string", "pattern": GEO_RE },
            "name": { "type": "string", "maxLength": 32 },
            "contact": { "type": "string", "maxLength": 32 },
            "firmware": { "type": "string", "maxLength": 32 },
            "community": { "type": "string", "maxLength": 32 },
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
            "geo": { "type": "string", "pattern": GEO_RE },
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

    ALIASES_SCHEMA = {
        "type": "object",
        "patternProperties": {
            MAC_RE : {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "geo": { "type": "array", "items": [{'type' : 'number'}, {'type' : 'number'}]},
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
    def parse_node(item):
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
        import zlib
        try:
            decompress = zlib.decompressobj(zlib.MAX_WBITS|32)
            # ignores any output beyond 64k (protection from zip bombs)
            properties = decompress.decompress(properties.encode('raw-unicode-escape'),64*1024).decode('utf-8')
        except zlib.error:
            properties = properties.encode('latin-1').decode('utf8')
            pass

        properties = json.loads(properties)
        jsonschema.validate(properties, AlfredParser.ALFRED_NODE_SCHEMA)

        # set some defaults for unspecified fields
        #properties.setdefault('name', mac)
        if 'geo' in properties:
            geo = properties['geo'].split()
            properties['geo'] = [ float(geo[0]), float(geo[1]) ]

        #properties.setdefault('contact', None)
        #properties.setdefault('firmware', None)
        #properties.setdefault('clientcount', 0)
        properties.setdefault('gateway', False)
        #properties.setdefault('community', None)
        properties.setdefault('vpn', False)
        properties.setdefault('links', [])
        links = properties['links']
        del properties['links']

        # create a Node and its Links from the data
        ret = Node(mac, properties, True)
        ret.update_links([Link(ret, link['smac'], link['dmac'], link.get('qual',0)/255.) for link in links])
        return ret

class Node:
    r'''
    A node in the freifunk network, identified by its primary MAC.
    '''
    def __init__(self, mac, properties, online):
        self.mac = mac
        self.properties = properties
        self.links = []
        self.online = online
        self.index = None # the index of this node in the list produced for ffmap

    def update_properties(self, properties, force):
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

    def update_links(self, links):
        r'''
        Extend the list of links of this node with `links`.
        '''
        self.links.extend(links)

    def ffmap(self):
        r'''
        Render this node (without its links) to a dictionary in a format
        understood by ffmap.
        '''
        properties = self.properties
        try:
            name = properties.get('name', None)
            contact = properties.get('contact', None)
            community = properties.get('community', None)
            firmware = properties.get('firmware', None)
            geo = properties.get('geo', None)
            clientcount = properties.get('clientcount', None)

            obj = {
                'id': self.mac,
                #'clientcount': properties['clientcount'],
                # ffmap looks at 'clients' to compute the number of clients for
                # its list view. We do not collect any information on the clients
                # (other than a count). So we need a list of 'null' values for
                # ffmap to be happy.
                #'clients': [None]*properties['clientcount'],
                'flags': {
                    "legacy": properties['firmware'] not in RECENT_FIRMWARES,
                    "gateway": properties['gateway'],
                    "vpn": properties["vpn"],
                    "online": self.online
                }
            }

            if name:
                obj['name'] = name

            if contact:
                obj['contact'] = contact

            if community:
                obj['community'] = community

            if firmware:
                obj['firmware'] = firmware

            if geo:
                obj['geo'] = geo

            if clientcount:
                obj['clientcount'] = clientcount

            return obj
        except KeyError as e:
            raise ValueError("node is missing required property '{0}'.".format(e.args[0]))

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
            'type': 'vpn' if self.source.properties['vpn'] or self.reverse.source.properties['vpn'] else None
        }

    # a printable representation
    def __repr__(self): return r'{0} (of {1}) -> {2} (of {3})'.format(self.smac, self.source.mac, self.dmac, self.reverse.source.mac if self.reverse else '?')

def render_ffmap(nodes):
    r'''
    Return a JSON representation of ``nodes`` which is understood by ffmap.
    '''
    ret = {}

    # render a timestamp
    import datetime
    ret['meta'] = { 'timestamp': datetime.datetime.utcnow().replace(microsecond=0).isoformat() }

    # render a list of nodes (without links)
    ret['nodes'] = []
    for i, node in enumerate(nodes):
        node.index = i
        ret['nodes'].append(node.ffmap())

    # a dictionary (smac,dmac)->link which is used to discover the reverse of
    # each link
    links = {}
    for node in nodes:
        for link in node.links:
            links[(link.smac, link.dmac)] = link

    # render a list of links
    ret['links'] = []
    for link in links.values():
        if link.reverse:
            continue

        try:
            reverse = links[(link.dmac, link.smac)]
        except KeyError:
            # commented because of too many error msgs
            #sys.stderr.write("Link {0} -> {1} has only been reported by one of its ends.\n".format(link.smac,link.dmac))
            continue

        link.reverse = reverse
        link.reverse.reverse = link

        ret['links'].append(link.ffmap())

    return ret

def main():
    import argparse, sys, json
    parser = argparse.ArgumentParser('Convert data received from alfred to a format accepted by ffmap-d3')
    parser.add_argument('-a', '--aliases', type=argparse.FileType('r'), help=r'a dictionary of overwrites to replace (offending) properties of some nodes')
    parser.add_argument('-m', '--maps', required=True, type=argparse.FileType('r'), help=r'input file containing data collected by alfred')
    parser.add_argument('-o', '--output', type=argparse.FileType('w'), default=sys.stdout,help=r'output file (default: stdout)')
    parser.add_argument('-c', '--communities', nargs='+', help=r'Communities we want to filter for. Show all if none defined.')
    args = parser.parse_args()

    nodes = {}
    for line in args.maps.readlines():
        try:
            node = AlfredParser.parse_node(line.strip())
        except:
            import traceback
            traceback.print_exc()
            continue

        #filter out unknown communities
        if args.communities and node.properties.get('community') not in args.communities:
            continue

        if node.mac in nodes:
            nodes[node.mac].update_properties(node.properties, True)
            nodes[node.mac].update_links(node.links)
        else:
            nodes[node.mac] = node

    if args.aliases:
        aliases = json.loads(args.aliases.read())
        jsonschema.validate(aliases, AlfredParser.ALIASES_SCHEMA)

        for mac, properties in aliases.items():
            node = nodes.get(mac, None);
            if node:
                force = properties.get("force", False)
                node.update_properties(properties, force)

    args.output.write(json.dumps(render_ffmap(nodes.values())))

if __name__ == '__main__':
    main()
