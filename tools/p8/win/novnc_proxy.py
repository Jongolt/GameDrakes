# P8: the noVNC page + WebSocket -> TightVNC (127.0.0.1:5900) on the Windows machine with Studio.
# HTTPS on 6080 (a self-signed certificate for the current public IP, reissued when the IP changes), HTTP on 6081 (fallback).
# Start: the P8-noVNC task (SYSTEM, at boot). Log: C:\p8\novnc_proxy.log
import asyncio, datetime, ipaddress, logging, os, ssl, urllib.request
from aiohttp import web, WSMsgType

BASE = r'C:\p8'
WEB = os.path.join(BASE, 'novnc')
TLS = os.path.join(BASE, 'tls')
VNC = ('127.0.0.1', 5900)
START = '/vnc.html?autoconnect=1&resize=scale&reconnect=1&reconnect_delay=3000&show_dot=1'
logging.basicConfig(filename=os.path.join(BASE, 'novnc_proxy.log'), level=logging.INFO,
                    format='%(asctime)s %(message)s')
log = logging.getLogger('p8')


def public_ip():
    try:
        req = urllib.request.Request('http://169.254.169.254/latest/api/token', method='PUT',
                                     headers={'X-aws-ec2-metadata-token-ttl-seconds': '60'})
        tok = urllib.request.urlopen(req, timeout=3).read().decode()
        req = urllib.request.Request('http://169.254.169.254/latest/meta-data/public-ipv4',
                                     headers={'X-aws-ec2-metadata-token': tok})
        return urllib.request.urlopen(req, timeout=3).read().decode().strip()
    except Exception as e:
        log.info('no public ip from IMDS: %r', e)
        return None


def ensure_cert(ip):
    os.makedirs(TLS, exist_ok=True)
    tag = ip or 'noip'
    crt, key = os.path.join(TLS, tag + '.crt'), os.path.join(TLS, tag + '.key')
    if os.path.exists(crt) and os.path.exists(key):
        return crt, key
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID
    k = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, ip or 'p8-studio')])
    san = [x509.DNSName('p8-studio')] + ([x509.IPAddress(ipaddress.ip_address(ip))] if ip else [])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(k.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1)).not_valid_after(now + datetime.timedelta(days=397))
            .add_extension(x509.SubjectAlternativeName(san), critical=False)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
            .sign(k, hashes.SHA256()))
    with open(key, 'wb') as f:
        f.write(k.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
                                serialization.NoEncryption()))
    with open(crt, 'wb') as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))
    log.info('new certificate for %s', tag)
    return crt, key


async def index(request):
    raise web.HTTPFound(START)


async def websockify(request):
    ws = web.WebSocketResponse(protocols=('binary',), max_msg_size=0, compress=False, heartbeat=30)
    await ws.prepare(request)
    peer = request.remote
    try:
        reader, writer = await asyncio.open_connection(*VNC)
    except Exception as e:
        log.info('%s: VNC connect failed %r', peer, e)
        await ws.close()
        return ws
    log.info('%s: connected', peer)

    async def vnc_to_ws():
        try:
            while True:
                data = await reader.read(262144)
                if not data:
                    break
                await ws.send_bytes(data)
        except Exception:
            pass
        finally:
            await ws.close()

    pump = asyncio.ensure_future(vnc_to_ws())
    try:
        async for msg in ws:
            if msg.type == WSMsgType.BINARY:
                writer.write(msg.data)
            elif msg.type == WSMsgType.TEXT:
                writer.write(msg.data.encode('latin-1'))
            else:
                break
            await writer.drain()
    except Exception:
        pass
    finally:
        pump.cancel()
        writer.close()
        log.info('%s: closed', peer)
    return ws


def quiet_errors(loop, ctx):
    # a connection drop by the client (WinError 10054) - normal, no traceback in the log
    log.info('loop: %s', ctx.get('exception') or ctx.get('message'))


async def main():
    asyncio.get_running_loop().set_exception_handler(quiet_errors)
    app = web.Application()
    app.router.add_get('/', index)
    app.router.add_get('/websockify', websockify)
    app.router.add_static('/', WEB, show_index=False)
    runner = web.AppRunner(app, access_log=None)
    await runner.setup()
    crt, key = ensure_cert(public_ip())
    ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ctx.load_cert_chain(crt, key)
    await web.TCPSite(runner, '0.0.0.0', 6080, ssl_context=ctx).start()
    await web.TCPSite(runner, '0.0.0.0', 6081).start()
    log.info('listening: https 6080, http 6081, cert %s', os.path.basename(crt))
    while True:
        await asyncio.sleep(3600)


if __name__ == '__main__':
    asyncio.run(main())
