# Dictionary of the Irish Language, offline

The whole electronic Dictionary of the Irish Language (eDIL) as a website that
runs on your own computer. You don't need an internet connection or any
software beyond a web browser.

## How to use it

### 1. Get a copy

**Easiest: download a ZIP (no tools needed)**

1. Click the green **Code** button near the top of this page, then
   **Download ZIP**. The file is about 40 MB.
2. Unzip it:
   - **Mac:** double-click the downloaded file.
   - **Windows:** right-click it and choose **Extract All…**, then **Extract**.

   You get a folder called `offline-eDIL-main`.

**Or, if you use git:**

```sh
git clone https://github.com/codestersunion/offline-eDIL.git
```

This makes a folder called `offline-eDIL`.

### 2. Open the dictionary

In the folder, open the **`static`** folder and double-click **`index.html`**.
It opens in your web browser. After a second or two of "Loading the
dictionary…" you can browse and search.

- Use the **Search** box at the top right. Accents and capitals don't matter:
  `run` finds *rún*. As you type it suggests headwords. Click one to open it,
  or press Enter to see all matches.
- **Headwords** lists every entry by letter, and **Browse** shows the pages of
  the printed dictionary column by column.
- To get back to it quickly, bookmark the page in your browser or make a
  shortcut to `index.html`.

### If something goes wrong

- **The page stays on "Loading the dictionary…" or shows an error:** update your
  browser. It needs a 2023 or newer version of Chrome, Edge, Firefox or Safari.
- **The page looks broken or empty:** make sure you unzipped the download
  first. Opening `index.html` from inside the ZIP without extracting it won't
  work.
- **You moved `index.html` on its own:** keep the whole `static` folder
  together. You can move or copy the folder anywhere, for example to a USB
  stick, as long as its contents stay together.

---

## About this project

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

### Run the server version

Requires Ruby 3.1+ (on macOS: `brew install ruby`).

```sh
bin/server
```

Then open http://localhost:4567. Set `PORT` to change the port, and `EDIL_DATA`
to load XML files from another directory.

### Build the browser-only version (no server)

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
