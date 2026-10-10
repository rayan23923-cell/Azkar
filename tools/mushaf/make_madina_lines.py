#!/usr/bin/env python3
"""Builds Packages/IslamicCore/Sources/QuranReading/Resources/MushafLines-Madina1421.txt.

The line breaks of the Madina mushaf (King Fahd Complex, 1421H print, 15 lines, 604 pages) are
taken from DigitalKhatt's page text (MIT licence):
  https://github.com/DigitalKhatt/digitalkhatt-js
  apps/site-angular/src/app/services/quran_text_madina.ts, commit 78372d7a1e21
Only where each line starts is kept. The text drawn is always the app's bundled Tanzil text;
this script checks that every verse's words and verse-end signs line up with it and stops if
one does not.

Output: one row per page; entries separated by spaces:
  H<surah>   the surah title band
  B          the basmala line
  s:a:w      a text line starting at word w (0-based) of verse s:a; w equal to the verse's word
             count means the line opens with that verse's end sign.

Usage: make_madina_lines.py quran_text_madina.ts quran.json output.txt
"""
import json
import re
import sys
import unicodedata


def is_word(token):
    return any(unicodedata.category(c) == 'Lo' for c in token)


def main(ts_path, quran_path, out_path):
    pages = [re.findall(r"'([^']*)'", block)
             for block in re.findall(r"\[\s*((?:'[^']*',?\s*)+)\]", open(ts_path, encoding='utf-8').read())]
    assert len(pages) == 604, len(pages)
    quran = json.load(open(quran_path, encoding='utf-8'))
    words, order = {}, []
    for surah in quran['surahs']:
        for ayah, text in enumerate(surah['verses'], 1):
            words[(surah['id'], ayah)] = sum(1 for t in text.split(' ') if is_word(t))
            order.append((surah['id'], ayah))

    vi = wi = 0
    awaiting_basmala = False
    rows = []
    for number, page in enumerate(pages, 1):
        row = []
        for line in page:
            if line.startswith('سُورَةُ '):
                assert wi == 0, (number, line)
                surah = order[vi][0]
                row.append(f'H{surah}')
                awaiting_basmala = surah not in (1, 9)
                continue
            if awaiting_basmala:
                assert '۝' not in line and len(line.split(' ')) == 4, (number, line)
                row.append('B')
                awaiting_basmala = False
                continue
            s, a = order[vi]
            row.append(f'{s}:{a}:{wi}')
            for token in line.split(' '):
                if token.startswith('۝'):
                    s, a = order[vi]
                    sign = int(''.join(str(ord(c) - 0x660) for c in token[1:]))
                    assert sign == a and wi == words[(s, a)], (number, s, a, sign, wi)
                    vi += 1
                    wi = 0
                elif is_word(token):
                    wi += 1
        rows.append(' '.join(row))
    assert vi == len(order) == 6236, vi
    with open(out_path, 'w', encoding='utf-8') as out:
        out.write('\n'.join(rows) + '\n')


if __name__ == '__main__':
    main(*sys.argv[1:4])
