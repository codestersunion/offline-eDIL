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
- In an entry, each form and each example sentence is on its own line. Point
  at an abbreviated source (dotted underline, like **Wb.**) to see its full
  title. An entry that just says "see …" shows the entry it points to
  underneath.
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
- **Entries** (`/entries/:id`): headword, the entry laid out for reading (see
  below), part of speech, definitions, sources
- **Search** (`/search?q=`): headwords (accent-insensitive, prefix) or definitions; typeahead in the navbar
- **Bibliography** (`/bibliography`): every cited source, linking to the entries that cite it
- **About** and **Contact**

There's no database. The first start parses and lays out all the XML (about
90 seconds) and caches the result in `data/.cache/`. Later starts take about
2 seconds. The cache rebuilds automatically when the XML, `data/sources.json`
or `lib/` changes.

### How entries are laid out

- **One line per form and per example** (`lib/entry_layout.rb`). The grammar
  block becomes a table with a row per run of labels ("ns.", "fut. 1 s.") and
  per form. Each sense lists its example sentences (Irish quotation,
  translation, references) one per line. Nothing is reworded or reordered:
  the entry only gains line breaks.
- **Source titles on hover** (`lib/source_markup.rb`, styles in
  `public/css/entry.css`). Abbreviations like "Wb." show the full reference,
  from `data/sources.json`. That file was built from eDIL's own bibliography
  pages, as saved by the Internet Archive, by `prototypes/build_sources.rb`.
  It covers 98.8% of the dictionary's references.
- **"See" entries** (`lib/cross_references.rb`). An entry like "acarda see
  accarda" shows the entries it points to underneath, following chains up to
  three steps. 96.8% of the 7,233 cross-reference entries resolve. Where the
  source spells the target differently by one letter, the box says it's the
  nearest match.

The browser-only version has a JavaScript copy of the layout rules in
`browser/app.js`. `test/layout_parity.rb` renders a sample of entries both
ways and checks the HTML is identical (it needs Google Chrome):

```sh
bin/build-static && ruby test/layout_parity.rb 4000
```

`prototypes/` holds the scripts used to design the layout: sample pages,
and a survey of how the rules handle every entry (`prototypes/survey.rb`).

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
  entry layout, search and pages as the server version. Pages are addressed
  by the URL hash, e.g. `index.html#/entries/35237`.
- It needs a browser from 2023 or later (Chrome, Edge, Firefox or Safari), for
  `DecompressionStream`. The page uses about 350 MB of memory once loaded.

Re-run `bin/build-static` after changing the XML, `lib/` or `browser/`.
