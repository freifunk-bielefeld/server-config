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
RECENT_FIRMWARES = ["ffbi-0.4.5", "server", None]

class AlfredParser:
    r'''
    A class providing static methods to parse and validate data reported by
    nodes via alfred.

    >>> AlfredParser.parse_node(r'{ "ca:ff:ee:ca:ff:ee", "{\"community\": \"ulm\", \"name\":\"MyNode\"}" },')
    Node('ca:ff:ee:ca:ff:ee', {'clientcount': 0,
     'community': 'ulm',
     'firmware': None,
     'gateway': False,
     'geo': None,
     'name': 'MyNode',
     'vpn': False}, online=True)

    The data is mostly JSON. However, alfred wraps it in a strange format which
    requires some manual parsing.
    The validation of the JSON entries is done through a `JSON Schema
    <http://json-schema.org/>`_.
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
        }
    }

    @staticmethod
    def _parse_string(s):
        r'''
        Strip an escaped string which is enclosed in double quotes and
        unescape. 

        >>> AlfredParser._parse_string(r'""')
        ''
        >>> AlfredParser._parse_string(r'"\""')
        '"'
        >>> AlfredParser._parse_string(r'"\"geo\""')
        '"geo"'
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

        >>> AlfredParser.parse_node(r'{ "fa:d1:11:79:38:32", "{\"community\": \"ulm\"}" },')
        Node('fa:d1:11:79:38:32', {'clientcount': 0,
         'community': 'ulm',
         'firmware': None,
         'gateway': False,
         'geo': None,
         'name': 'fa:d1:11:79:38:32',
         'vpn': False}, online=True)

        >>> AlfredParser.parse_node(r'{ "fa:d1:11:79:38:32", "{\"community\": \"ulm\", \"invalid\": \"property\"}" },') # doctest: +ELLIPSIS
        Traceback (most recent call last):
        ...
        jsonschema.exceptions.ValidationError: Additional properties are not allowed ('invalid' was unexpected)
        ...

        The second entry might by gzipped.

        >>> AlfredParser.parse_node(r'{ "02:16:3c:03:35:e0", "\x1f\x8b\x08\x00S\xcb\xbfT\x00\x03\x95\x90A\x0e\xc2 \x14D\xafBXwA\x91j;W1.\x08\xfd\x98\xc6\x82J\xa1\xc6\x98\xde\xdd\x821\xd1\xb8r\xf7\xe7M\xe6-\xfe\x83{\xed\x8830>_\xbc\xe4\x15\xe3v\x08\xee\xa6\xc3\x0bN\x14f\x0a\x19\x9b\xb3s\xc9\x0f\xf1^x\x1a]\x86G\x1d\xe9\xa6\x0b\x8a!QU,\x1fi\x1c\xfci\xcay\xffX]N\x9b2\x96\x1au\x07c\xd1\x13L\x87]\x9bU\xfd\xbb\x15\x12\xaa\x83\xdd@\xb5h-\x1a\x95\xdbk\xd2cne#\xd9R\xb1\xbfl\xb5\x86R\x905:\xb1\x1e\xdf\xb6\xe6o\x1b\x11z\x81z\x0b\xb5\x83\xb0?\xb6C~\xd58\x90\x8f\xe6\x9c|\xcc\\,O\xa3\xcb\xb1Af\x01\x00\x00" },')
        Node('02:16:3c:03:35:e0', {'clientcount': 0,
         'community': 'ulm',
         'firmware': 'server',
         'gateway': True,
         'geo': None,
         'name': 'vpn2',
         'vpn': True}, online=True)

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
        else:
            properties['geo'] = None

        #properties.setdefault('contact', None)
        #properties.setdefault('firmware', None)
        properties.setdefault('clientcount', 0)
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

    >>> Node('fa:d1:11:79:38:32', { 'community': 'ulm' }, online=True)
    Node('fa:d1:11:79:38:32', {'community': 'ulm'}, online=True)

    The second parameter is a dictionary of attributes (e.g. as reported
    through alfred.)
    Links can be added to a node through :meth:`update_links`.
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

        >>> node = Node('fa:d1:11:79:38:32', { 'community': 'ulm' }, online=True)
        >>> node.update_properties({'community': 'ulm'})
        >>> node
        Node('fa:d1:11:79:38:32', {'community': 'ulm'}, online=True)

        '''
        if force:
            ''' merge/overwrite values '''
            self.properties.update(properties)
        else:
            ''' add new key/value pairs only if not already set '''
            for key, value in properties.items():
                if key != "force" and not key in self.properties:
                    self.properties[key] = value

    def update_links(self, links):
        r'''
        Extend the list of links of this node with `links`.

        >>> node = Node('fa:d1:11:79:38:32', { 'community': 'ulm' }, online=True)
        >>> node.links
        []
        >>> node.update_links([Link(node, 'fa:d1:11:79:38:32', 'af:d1:11:79:38:32', .5)])
        >>> node.links
        [fa:d1:11:79:38:32 (of fa:d1:11:79:38:32) -> af:d1:11:79:38:32 (of ?)]

        '''
        self.links.extend(links)

    def ffmap(self):
        r'''
        Render this node (without its links) to a dictionary in a format
        understood by ffmap.

        >>> node = AlfredParser.parse_node(r'{ "fa:d1:11:79:38:32", "{\"community\":\"ulm\"}" },')
        >>> pprint(node.ffmap())
        {'clientcount': 0,
         'clients': [],
         'community': 'ulm',
         'firmware': None,
         'flags': {'gateway': False, 'legacy': True, 'online': True, 'vpn': False},
         'geo': None,
         'id': 'fa:d1:11:79:38:32',
         'name': 'fa:d1:11:79:38:32'}

        This method requires some properties to be set::

        >>> del(node.properties['geo'])
        >>> node.ffmap()
        Traceback (most recent call last):
        ...
        ValueError: node is missing required property 'geo'.

        '''
        properties = self.properties
        try:
            name = properties.get('name', None)
            contact = properties.get('contact', None)
            community = properties.get('community', None)
            firmware = properties.get('firmware', None)

            obj = {
                'id': self.mac,
                'geo': properties['geo'],
                'clientcount': properties['clientcount'],
                # ffmap looks at 'clients' to compute the number of clients for
                # its list view. We do not collect any information on the clients
                # (other than a count). So we need a list of 'null' values for
                # ffmap to be happy.
                'clients': [None]*properties['clientcount'],
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

    >>> node1 = Node('fa:d1:11:79:38:32', { 'community': 'ulm' }, online=True)
    >>> node2 = Node('fb:d1:11:79:38:32', { 'community': 'ulm' }, online=True)
    >>> l12 = Link(node1, 'fa:d2:11:79:38:32', 'fb:d2:11:79:38:32', 1.0)
    >>> l12
    fa:d2:11:79:38:32 (of fa:d1:11:79:38:32) -> fb:d2:11:79:38:32 (of ?)
    >>> l21 = Link(node2, 'fb:d2:11:79:38:32', 'fa:d2:11:79:38:32',  .5)
    >>> l21.reverse = l12
    >>> l12.reverse = l21
    >>> l12
    fa:d2:11:79:38:32 (of fa:d1:11:79:38:32) -> fb:d2:11:79:38:32 (of fb:d1:11:79:38:32)

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

        >>> node1 = Node('fa:d1:11:79:38:32', { 'community': 'ulm', 'vpn': True }, online=True)
        >>> node2 = Node('fb:d1:11:79:38:32', { 'community': 'ulm', 'vpn': False }, online=True)
        >>> l12 = Link(node1, 'fa:d2:11:79:38:32', 'fb:d2:11:79:38:32', 1.0)
        >>> l21 = Link(node2, 'fb:d2:11:79:38:32', 'fa:d2:11:79:38:32',  .5)
        
        A link does not render until its ``reverse`` and ``index`` has been set
        (this is done automatically by :meth:`render_ffmap`.)

        >>> l12.ffmap()
        Traceback (most recent call last):
        ...
        ValueError: link must have 'reverse' set to render to ffmap
        >>> l21.reverse = l12
        >>> l12.reverse = l21
        >>> l12.ffmap()
        Traceback (most recent call last):
        ...
        ValueError: link's source and target must have their 'index' set to render to ffmap

        >>> node1.index = 0
        >>> node2.index = 1
        >>> pprint(l12.ffmap())
        {'id': 'fa:d2:11:79:38:32-fb:d2:11:79:38:32',
         'quality': '1.000, 0.500',
         'source': 0,
         'target': 1,
         'type': 'vpn'}

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

    >>> node1 = AlfredParser.parse_node(r'{ "fa:d1:11:79:38:32", "{\"community\": \"ulm\"}" },')
    >>> node2 = AlfredParser.parse_node(r'{ "fb:d1:11:79:38:32", "{\"community\": \"ulm\"}" },')
    >>> l12 = Link(node1, 'fa:d2:11:79:38:32', 'fb:d2:11:79:38:32', 1.0)
    >>> l21 = Link(node2, 'fb:d2:11:79:38:32', 'fa:d2:11:79:38:32',  .5)
    >>> node1.update_links([l12])
    >>> node2.update_links([l21])
    >>> pprint(render_ffmap([node1, node2])) # doctest: +ELLIPSIS
    {'links': [{'id': 'fa:d2:11:79:38:32-fb:d2:11:79:38:32',
                'quality': '1.000, 0.500',
                'source': 0,
                'target': 1,
                'type': None}],
     'meta': {'timestamp': '...'},
     'nodes': [{'clientcount': 0,
                'clients': [],
                'community': 'ulm',
                'firmware': None,
                'flags': {'gateway': False,
                          'legacy': True,
                          'online': True,
                          'vpn': False},
                'geo': None,
                'id': 'fa:d1:11:79:38:32',
                'name': 'fa:d1:11:79:38:32'},
               {'clientcount': 0,
                'clients': [],
                'community': 'ulm',
                'firmware': None,
                'flags': {'gateway': False,
                          'legacy': True,
                          'online': True,
                          'vpn': False},
                'geo': None,
                'id': 'fb:d1:11:79:38:32',
                'name': 'fb:d1:11:79:38:32'}]}

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
