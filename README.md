# eDIL (local)

A small Sinatra rewrite of the 2012 eDIL prototype
([e-dil/eDIL](https://github.com/e-dil/eDIL)), which needed Rails 3.2 /
Ruby 1.9.3. The dictionary text in `data/` comes from the `xml/` folder of
[e-dil/dil](https://github.com/e-dil/dil): 19 files (A–U, with D in two
parts), about 42,700 entries. H is nearly empty in that source (31 entries).

Pages:

- **Browse** (`/columns/:section/:n`): the printed edition, two columns per page, with line numbers
- **Entries** (`/entries/:id`): headword, formatted body, part of speech, definitions, sources
- **Search** (`/search?q=`): headwords (accent-insensitive, prefix) or definitions; typeahead in the navbar
- **Bibliography** (`/bibliography`): every cited source, linking to the entries that cite it
- **About** and **Contact**

There's no database. The first start parses all the XML (about 50 seconds) and
caches the result in `data/.cache/`. Later starts take about 2 seconds. The
cache rebuilds automatically when the XML or `lib/` changes.

## Run

Requires Ruby 3.1+ (on macOS: `brew install ruby`).

```sh
bin/server
```

Then open http://localhost:4567. Set `PORT` to change the port, and `EDIL_DATA`
to load XML files from another directory.

## Browser-only version (no server)

```sh
bin/build-static
```

This writes `static/` (about 27 MB). Open `static/index.html` straight from
disk, by double-clicking it or from a `file://` address. Nothing needs to be
running. The folder is self-contained, so you can copy it anywhere.

A built copy of `static/` is committed to this repo, so you can use it without
running the build.

- `data.js` holds the whole dictionary as gzipped JSON in base64. A page opened
  from disk may load scripts but not fetch data files, which is why it's a script.
- `app.js` (source: `browser/app.js`) decompresses it on load, which takes
  about half a second. It then draws each page on demand, with the same
  markup rendering, search and page layout as the server version. Pages
  are addressed by the URL hash, e.g. `index.html#/entries/35237`.
- It needs a browser from 2023 or later (Chrome, Edge, Firefox or Safari), for
  `DecompressionStream`. The page uses about 350 MB of memory once loaded.

Re-run `bin/build-static` after changing the XML, `lib/` or `browser/`.
