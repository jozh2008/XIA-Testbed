from __future__ import print_function

import hashlib
import re
import urllib2
import urlparse
import xml.etree.ElementTree as ET

opener = urllib2.build_opener(urllib2.ProxyHandler({
    'http': 'http://127.0.0.1:8080'
}))

def fetch(url):
    # The legacy proxy recognises lowercase 'dag' hostnames and restores
    # uppercase XID labels itself. Normalise the authority like a browser;
    # preserve the case of paths and query strings.
    parts = urlparse.urlsplit(url)
    url = urlparse.urlunsplit((parts.scheme, parts.netloc.lower(),
                              parts.path or '/', parts.query, parts.fragment))
    response = opener.open(url, timeout=10)
    try:
        if response.getcode() != 200:
            raise RuntimeError('Unexpected HTTP status: %s' % response.getcode())
        return response.read()
    finally:
        response.close()

root = ET.fromstring(fetch('http://www.origin.xia/synthetic12.mpd'))
ns = {'d': 'urn:mpeg:dash:schema:mpd:2011'}
initialization = root.find('.//d:Initialization', ns)
segments = root.findall('.//d:SegmentURL', ns)
if initialization is None or len(segments) != 6:
    raise RuntimeError('Expected initialization and six video segments')

entries = [('Initialization', initialization.get('sourceURL'))]
entries += [('Segment %d' % (i + 1), node.get('media'))
            for i, node in enumerate(segments)]
total = 0
for label, url in entries:
    if not url or len(url.split()) != 1:
        raise RuntimeError('Expected one chunk URL per file')
    match = re.search(r'CID\$([0-9a-fA-F]{40})/?$', url)
    if not match:
        raise RuntimeError('Cannot extract CID from URL')
    print('Fetching %s...' % label)
    data = fetch(url)
    if not data or hashlib.sha1(data).hexdigest() != match.group(1).lower():
        raise RuntimeError('%s: empty data or CID checksum mismatch' % label)
    total += len(data)
    print('%s: %d bytes, CID OK' % (label, len(data)))
print('SUCCESS: all 7 files fetched and verified (%d bytes)' % total)
