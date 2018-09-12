module.exports = function () {
  return {
    // Variables are NODE_ID and NODE_NAME (only a-z0-9\- other chars are replaced with _)
    'nodeInfos': [
    /*
      {
        'name': 'Clientstatistik',
        'href': 'https://regensburg.freifunk.net/netz/statistik/node/{NODE_ID}/',
        'image': 'https://grafana.regensburg.freifunk.net/render/d-solo/000000026/node?panelId=1&var-node={NODE_ID}&from=now-7d&width=650&height=350&theme=light&_t={TIME}',
        'title': 'Knoten {NODE_ID} - weiteren Statistiken'
      },
      {
        'name': 'Trafficstatistik',
        'href': 'https://regensburg.freifunk.net/netz/statistik/node/{NODE_ID}/',
        'image': 'https://grafana.regensburg.freifunk.net/render/d-solo/000000026/node?panelId=2&from=now-7d&var-node={NODE_ID}&width=650&height=350&theme=light&_t={TIME}',
        'title': 'Knoten {NODE_ID} - weiteren Statistiken'
      },
      {
        'name': 'Airtime',
        'href': 'https://regensburg.freifunk.net/netz/statistik/node/{NODE_ID}/',
        'image': 'https://grafana.regensburg.freifunk.net/render/d-solo/000000026/node?panelId=5&from=now-7d&var-node={NODE_ID}&width=650&height=350&theme=light&_t={TIME}',
        'title': 'Knoten {NODE_ID} - weiteren Statistiken'
      }
      */
    ],
    'linkInfos': [
      /*{
        'name': 'Statistik für alle Links zwischen diese Knoten',
        'image': 'https://grafana.regensburg.freifunk.net/render/d-solo/000000026/node?panelId=7&var-node={SOURCE_ID}&var-nodetolink={TARGET_ID}&from=now-7d&&width=650&height=350&theme=light&_t={TIME}',
        'title': 'Linkstatistik des letzten Tages, min und max aller Links zwischen diesen Knoten'
      }*/
    ],
    // Array of data provider are supported
    'dataPath': [
      'data/'
    ],
    'siteName': 'Freifunk Bielefeld',
    'mapLayers': [
      {
        'name': 'Freifunk Bielefeld',
        // Please ask Freifunk Bielefeld before using its tile server c- example with retina tiles
        'url': 'http://tiles.freifunk-bielefeld.de/{z}/{x}/{y}.png',
        'config': {
          'maxZoom': 20,
          'subdomains': '1234',
          'attribution': '<a href="http://www.openmaptiles.org/" target="_blank">&copy; OpenMapTiles</a> <a href="http://www.openstreetmap.org/about/" target="_blank">&copy; OpenStreetMap contributors</a>',
          'start': 6
        }
      },
      {
        'name': 'OpenStreetMap.HOT',
        'url': 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
        'config': {
          'maxZoom': 19,
          'attribution': '&copy; Openstreetmap France | &copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        }
      },
      {
        'name': 'Esri.WorldImagery',
        'url': '//server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        'config': {
          'maxZoom': 20,
          'attribution': 'Tiles &copy; Esri &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community'
        }
      }
    ],
    // Set a visible frame
    'fixedCenter': [
    // Northwest
      [
        52.334080,
        8.302231
      ],
      // Southeast
      [
        51.951037,
        9.157791
      ]
    ],

    'siteNames': [
      { "site" : "bielefeld", "name": "Bielefeld", "link" : "http://freifunk-bielefeld.de" },
      { "site" : "obernkirchen", "name": "Obernkirchen", "link" : "http://www.freifunk-obernkirchen.de" },
      { "site" : "badoeynhausen", "name": "Bad Oeynhausen", "link" : "https://www.freifunk-badoeynhausen.de" },
      { "site" : "minden", "name": "Minden", "link" : "http://www.freifunk-minden.de" },
      { "site" : "herford", "name": "Herford", "link" : "http://herford.freifunk.net" },
      { "site" : "bad-pyrmont", "name": "Bad-Pyrmont" },
      { "site" : "rinteln", "name": "Rinteln" },
      { "site" : "loehne", "name": "Löhne" },
      { "site" : "hildesheim", "name": "Hildesheim", "link" : "http://freifunk-hi.de" },
      { "site" : "lemgo", "name" : "Lemgo", "link" : "https://www.freifunk-lemgo.de" },
      { "site" : "vlotho", "name" : "Vlotho" },
      { "site" : "bueckeburg", "name" : "Bückeburg" },
      { "site" : "petershagen", "name" : "Petershagen" },
      { "site" : "lage", "name": "Lage" }
    ],
    'linkList': [
      {
        'title': 'Impressum',
        'href': '/verein/impressum/'
      },
      {
        'title': 'Datenschutz',
        'href': '/verein/datenschutz/'
      }
    ]
  };
};

