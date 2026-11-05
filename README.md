# Dictionary of the Irish Language, offline

Since dil.ie has been down for quite a while now, I had Claude create an offline version of the DIL for reference. I used the dictionary files available at https://github.com/e-dil/dil to supply the text. Instructions below.

The whole electronic Dictionary of the Irish Language (eDIL) as a website that
runs on your own computer. Once it's built, you only need a web browser, with
no internet connection.

This repository holds the program, not the dictionary itself. Building the
site downloads the dictionary text from [e-dil/dil](https://github.com/e-dil/dil)
(about 80 MB) and turns it into a folder you can open in any browser. You do
this once; it takes about two minutes.

## How to build it

You type a few commands into a terminal window. Each step says exactly what
to type: copy the line, paste it into the terminal, and press Enter.

### 1. Install Ruby (once)

The build is a small program in the Ruby language. You need Ruby 3.1 or newer.

#### On a Mac

1. Open **Terminal** (in Applications → Utilities, or search for it with
   Spotlight, ⌘-Space).
2. Install [Homebrew](https://brew.sh), which installs Ruby for you. Copy
   the install command from the top of brew.sh, paste it into Terminal and
   press Enter. It asks for your Mac password (nothing appears on screen as
   you type it, which is normal) and may install Apple's "Command Line
   Tools", which takes a few minutes.
3. When Homebrew finishes, it prints **Next steps** with two or three
   commands to run. Run them: on newer Macs, that's what makes the `brew`
   command work. Then check with `brew -v`, which should print a version.
4. Install Ruby:

   ```sh
   brew install ruby
   ```

5. Make Homebrew's Ruby the one Terminal uses. macOS comes with an old Ruby
   (2.6) that is too old, and Homebrew doesn't replace it on its own:

   ```sh
   echo 'export PATH="$(brew --prefix ruby)/bin:$PATH"' >> ~/.zprofile
   ```

6. **Quit Terminal (⌘-Q) and open it again.** Then run `ruby -v`. It should
   print a version of 3.1 or higher (`ruby 3.4.7`, say). If it still says `ruby 2.6`,
   see [If something goes wrong](#if-something-goes-wrong).

#### On Windows

1. Go to [rubyinstaller.org/downloads](https://rubyinstaller.org/downloads/)
   and download the installer marked **=>** under **WITH DEVKIT** (it
   looks like *Ruby+Devkit 3.x.x-1 (x64)*; a higher version number is fine).
2. Run it and keep the default options. In particular, leave **Add Ruby
   executables to your PATH** ticked.
3. On the last screen, leave **Run 'ridk install'** ticked and click
   **Finish**. A black window opens and asks which components to install:
   just press **Enter**. Wait until it says it's done (several minutes),
   then press Enter again to close it.
4. Check: open the Start menu, type `cmd`, open **Command Prompt**, and run
   `ruby -v`. It should print a version of 3.1 or higher.

#### On Linux

Install Ruby and Bundler with your package manager:

- Debian 12+, Ubuntu 24.04+: `sudo apt install ruby-full ruby-bundler`
- Fedora: `sudo dnf install ruby rubygem-bundler`

Then run `ruby -v`. Some older releases (for example Ubuntu 22.04) have
Ruby 3.0, which is too old; there, install a newer Ruby with
[rbenv](https://github.com/rbenv/rbenv) or upgrade the system.

### 2. Get the code

Click the green **Code** button near the top of this page, then **Download
ZIP**, and unzip it: double-click it on a Mac; on Windows, right-click it and
choose **Extract All…**. You get a folder called `offline-eDIL-main`. (On
Windows it is sometimes inside another folder of the same name: use the inner
one, the one that contains a file called `Gemfile`.)

Or, if you use git:

```sh
git clone https://github.com/codestersunion/offline-eDIL.git
```

### 3. Build the site

First, open a terminal **in that folder**:

- **Mac:** in Terminal, type `cd` and a space (don't press Enter yet), drag
  the `offline-eDIL-main` folder from Finder onto the Terminal window, then
  press Enter.
- **Windows:** open the folder in File Explorer, click in the address bar at
  the top, type `cmd` and press Enter. A Command Prompt opens in that folder.
- **Linux:** `cd` into the folder.

Then run these two commands, one after the other:

```sh
bundle install
bundle exec ruby bin/build-static
```

`bundle install` installs the few libraries the build uses, into a
`vendor` folder inside this one (so it never needs your password).
`bin/build-static` downloads the dictionary text, checks it, and writes the
finished site to the **`static`** folder. The first build takes a few
minutes; it's finished when it prints `Wrote ... Open static/index.html in a
browser.`

### 4. Open the dictionary

Open the **`static`** folder and double-click **`index.html`**. It opens in
your web browser. After a second or two of "Loading the dictionary…" you can
browse and search. The `static` folder is self-contained (about 27 MB): copy
it anywhere, or to another computer, and it still works. You don't need Ruby
or the rest of this folder to use it.

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

- **Mac: `ruby -v` still says 2.6, or `bundle install` says your Ruby
  version is too old:** Terminal is using macOS's Ruby. Make sure you ran
  the `echo ... >> ~/.zprofile` command in step 1, then quit Terminal
  completely (⌘-Q) and open it again.
- **Mac: `brew: command not found`:** run the **Next steps** commands that
  the Homebrew installer printed, then open a new Terminal window. If you
  closed it already, run the installer again; it prints them again.
- **`ruby` or `bundle` is "not recognized" / "command not found":** open a
  *new* terminal window after installing Ruby; windows that were already
  open don't see it. On Windows, if that doesn't help, run the installer
  again and make sure **Add Ruby executables to your PATH** is ticked.
- **`Could not locate Gemfile`:** the terminal isn't in the right folder.
  Go back to the start of step 3; the folder you open must contain a file
  called `Gemfile`.
- **`bundle install` fails while installing nokogiri:** your computer needs
  build tools for it. On a Mac run `xcode-select --install`; on Windows run
  `ridk install` and enter `3`; on Linux install `build-essential` (or your
  system's equivalent). Then run `bundle install` again.
- **The build says it could not download the dictionary data:** check your
  internet connection and run the build again. It only downloads what's
  missing, and checks every file against a fixed checksum.
- **There's no `static` folder:** the build hasn't finished; see step 3.
- **The page stays on "Loading the dictionary…" or shows an error:** update
  your browser. It needs a 2023 or newer version of Chrome, Edge, Firefox or
  Safari.
- **You moved `index.html` on its own:** keep the whole `static` folder
  together. You can move or copy the folder anywhere, for example to a USB
  stick, as long as its contents stay together.

---

## About this project

A small Sinatra rewrite of the 2012 eDIL prototype
([e-dil/eDIL](https://github.com/e-dil/eDIL)), which needed Rails 3.2 /
Ruby 1.9.3.

The dictionary text comes from the `xml/` folder of
[e-dil/dil](https://github.com/e-dil/dil): 19 files (A–U, with D in two
parts), about 42,700 entries. H is nearly empty in that source (31 entries).
It is not stored in this repository. `bin/fetch-data` downloads it into
`data/` from one fixed commit of e-dil/dil (`c3fc5b4`) and checks each file's
SHA-256 checksum, so every build uses exactly the same text. `bin/server` and
`bin/build-static` run it automatically. Set `EDIL_DATA` to keep the files in
another directory.

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
bundle exec ruby bin/build-static && bundle exec ruby test/layout_parity.rb 4000
```

`prototypes/` holds the scripts used to design the layout: sample pages,
and a survey of how the rules handle every entry (`prototypes/survey.rb`).

### Run the server version

Set up Ruby as in step 1 above, then, in this folder:

```sh
bin/server
```

On Windows, double-click `server.cmd` in the `bin` folder, or run
`bin\server` in a Command Prompt. Then open http://localhost:4567. Set `PORT` to change the port, and `EDIL_DATA`
to load XML files from another directory.

### Build the browser-only version (no server)

```sh
bundle exec ruby bin/build-static
```

This writes `static/` (about 27 MB). Open `static/index.html` straight from
disk, by double-clicking it or from a `file://` address. Nothing needs to be
running. The folder is self-contained, so you can copy it anywhere. It is
built output and not stored in the repository, since it contains the
dictionary.

- `data.js` holds the whole dictionary as gzipped JSON in base64. A page opened
  from disk may load scripts but not fetch data files, which is why it's a script.
- `app.js` (source: `browser/app.js`) decompresses it on load, which takes
  about half a second. It then draws each page on demand, with the same
  entry layout, search and pages as the server version. Pages are addressed
  by the URL hash, e.g. `index.html#/entries/35237`.
- It needs a browser from 2023 or later (Chrome, Edge, Firefox or Safari), for
  `DecompressionStream`. The page uses about 350 MB of memory once loaded.

Re-run `bin/build-static` after changing the XML, `lib/` or `browser/`.
