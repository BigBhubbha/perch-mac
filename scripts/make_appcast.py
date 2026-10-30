#!/usr/bin/env python3
"""Writes a one-item Sparkle appcast for the release being published.

usage: make_appcast.py OUT VERSION BUILD URL LENGTH ED_SIGNATURE NOTES_MD
"""
import html, sys
from email.utils import formatdate

out, version, build, url, length, sig, notes_path = sys.argv[1:8]

parts, items = [], []
for raw in open(notes_path, encoding="utf-8").read().splitlines():
    line = raw.strip()
    if line.startswith("- "):
        items.append(f"<li>{html.escape(line[2:])}</li>")
        continue
    if items:
        parts.append("<ul>" + "".join(items) + "</ul>")
        items = []
    if line:
        parts.append(f"<p>{html.escape(line)}</p>")
if items:
    parts.append("<ul>" + "".join(items) + "</ul>")
notes_html = "\n".join(parts)

xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Perch</title>
    <link>https://github.com/BigBhubbha/perch-mac</link>
    <description>Updates for Perch for Mac</description>
    <language>en</language>
    <item>
      <title>Perch {html.escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
{notes_html}
      ]]></description>
      <enclosure url="{html.escape(url)}" length="{html.escape(length)}" type="application/octet-stream" sparkle:edSignature="{html.escape(sig)}"/>
    </item>
  </channel>
</rss>
"""
open(out, "w", encoding="utf-8").write(xml)
print(xml)
