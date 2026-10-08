import hashlib, json, os, sys, time, urllib.request, urllib.error
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15'
out = 'probe/hisn'
os.makedirs(out + '/shamela', exist_ok=True)
log = []
def get(url, timeout=60):
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            return e.code, b''
        except Exception as e:
            log.append(f'retry {attempt} {url} {e!r}')
            time.sleep(2 ** attempt)
    return 0, b''

# Author's official pages and PDF
pdf_url = 'https://cdn.binwahaf.com/uploads/2025/12/' + urllib.parse.quote('حصن-المسلم-من-أذكاء-الكتاب-والسنة.pdf') if False else None
import urllib.parse
pdf_url = 'https://cdn.binwahaf.com/uploads/2025/12/' + urllib.parse.quote('حصن-المسلم-من-أذكاء-الكتاب-والسنة.pdf')
for name, url in [('binwahaf_book_854.html', 'https://binwahaf.com/ar/book/854/'),
                  ('binwahaf_audio_series_897.html', 'https://binwahaf.com/ar/audio-book-series/897/'),
                  ('author.pdf', pdf_url)]:
    st, body = get(url, 120)
    log.append(f'{st} {len(body)} {url}')
    if body:
        open(f'{out}/{name}', 'wb').write(body)
        log.append(f'sha256 {name} {hashlib.sha256(body).hexdigest()}')

# Shamela transcription (cross-check source), page by page
empty = 0
for p in range(1, 220):
    st, body = get(f'https://shamela.ws/book/31307/{p}')
    log.append(f'shamela {p} {st} {len(body)}')
    if st == 200 and body:
        open(f'{out}/shamela/{p:03d}.html', 'wb').write(body)
        empty = 0
    else:
        empty += 1
        if empty >= 3:
            break
    time.sleep(0.7)
open(f'{out}/fetch.log', 'w').write('\n'.join(log) + '\n')
