# a browser check of noVNC: Edge headless + DevTools, wait for the connection, status and a snapshot -> C:\p8\edge.png. The VNC password from stdin.
import asyncio, base64, subprocess, sys
import aiohttp
pw = sys.stdin.readline().strip()
edge = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
url = 'https://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale&password=' + pw
p = subprocess.Popen([edge, '--headless=new', '--ignore-certificate-errors', r'--user-data-dir=C:\p8\edgetest', '--no-first-run',
                      '--window-size=1440,900', '--remote-debugging-port=9333', 'about:blank'])

async def main():
    async with aiohttp.ClientSession() as s:
        tabs = None
        for _ in range(30):
            try:
                async with s.get('http://127.0.0.1:9333/json') as r:
                    tabs = await r.json(); break
            except Exception:
                await asyncio.sleep(1)
        ws_url = [t for t in tabs if t.get('type') == 'page'][0]['webSocketDebuggerUrl']
        async with s.ws_connect(ws_url, max_msg_size=0) as ws:
            n = [0]
            async def call(method, params=None):
                n[0] += 1; mid = n[0]
                await ws.send_json({'id': mid, 'method': method, 'params': params or {}})
                while True:
                    m = await ws.receive_json()
                    if m.get('id') == mid:
                        return m
            await call('Page.enable')
            await call('Page.navigate', {'url': url})
            await asyncio.sleep(15)
            js = "(document.getElementById('noVNC_status')||{}).textContent + ' | canvas=' + (document.querySelector('#noVNC_container canvas')||{}).width + 'x' + (document.querySelector('#noVNC_container canvas')||{}).height + ' | ' + navigator.userAgent"
            st = await call('Runtime.evaluate', {'expression': js, 'returnByValue': True})
            print('page:', st.get('result', {}).get('result', {}).get('value'))
            shot = await call('Page.captureScreenshot', {'format': 'png'})
            open(r'C:\p8\edge.png', 'wb').write(base64.b64decode(shot['result']['data']))
            print('saved')

try:
    asyncio.run(main())
finally:
    p.kill()
