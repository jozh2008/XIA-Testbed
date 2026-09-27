#!/usr/bin/env python3
"""Local playback harness for the synthetic12 XIA demo (Python stdlib only).

Run on the Mac with Docker access; open http://127.0.0.1:8765/.
The three XIA video programs must already be running. Each fetch goes via
docker exec into host0, its HTTP proxy on port 8080, and then XIA.
This is a functional single-representation player, not a benchmark or ABR test.
"""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import parse_qs, urlsplit, urlunsplit

DOCKER = shutil.which('docker')
MANIFEST = 'http://www.origin.xia/synthetic12.mpd'
PAGE = Path(__file__).with_name('player.html')

# stdout contains only the HTTP response body, never debug output.
FETCH_CODE = '''
import http.client, sys
c = http.client.HTTPConnection('127.0.0.1', 8080, timeout=15)
try:
    c.request('GET', sys.argv[1], headers={'Connection': 'close'})
    r = c.getresponse()
    if r.status != 200:
        raise RuntimeError('Proxy returned HTTP %s' % r.status)
    body = r.read(4 * 1024 * 1024 + 1)
    if len(body) > 4 * 1024 * 1024:
        raise RuntimeError('Response exceeds test limit')
    sys.stdout.buffer.write(body)
finally:
    c.close()
'''

def fetch_xia(url):
    parts = urlsplit(url)
    # The legacy proxy expects lowercase URL authorities.
    target = urlunsplit((parts.scheme, parts.netloc.lower(),
                        parts.path or '/', parts.query, ''))
    result = subprocess.run(
        [DOCKER, 'exec', '-i', 'host0', 'python3', '-c', FETCH_CODE, target],
        capture_output=True, timeout=25)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', 'replace')[-1800:])
    return result.stdout

def chunk_cid(url):
    # Accept only the demo's single-chunk DAG addresses, not arbitrary hosts.
    match = re.fullmatch(
        r'http://dag\.[a-z0-9.$-]+\.cid\$([0-9a-f]{40})/?', url, re.I)
    if not match:
        raise ValueError('Unexpected segment URL; expected one XIA DAG/CID')
    return match.group(1).lower()

class Handler(BaseHTTPRequestHandler):
    def reply(self, code, data, content_type):
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        try:
            route = urlsplit(self.path)
            if route.path == '/':
                self.reply(200, PAGE.read_bytes(), 'text/html; charset=utf-8')
            elif route.path == '/manifest':
                self.reply(200, fetch_xia(MANIFEST), 'application/dash+xml')
            elif route.path == '/chunk':
                url = parse_qs(route.query).get('url', [''])[0]
                expected = chunk_cid(url)
                data = fetch_xia(url)
                if not data or hashlib.sha1(data).hexdigest() != expected:
                    raise RuntimeError('CID checksum mismatch or empty response')
                self.reply(200, data, 'video/mp4')
            else:
                self.reply(404, b'Not found', 'text/plain')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:
            message = str(exc) or type(exc).__name__
            print('Fetch failed:', message, flush=True)
            self.reply(502, message.encode('utf-8'), 'text/plain; charset=utf-8')

if __name__ == '__main__':
    if not DOCKER:
        raise SystemExit('docker was not found in PATH')
    server = ThreadingHTTPServer(('127.0.0.1', 8765), Handler)
    server.daemon_threads = True
    print('XIA video test: http://127.0.0.1:8765/', flush=True)
    print('Keep this terminal open. Ctrl+C stops only this local test server.', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
