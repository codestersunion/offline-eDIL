# Checks that the browser-only build lays entries out exactly as the server
# does: renders a sample of entries with lib/entry_layout.rb and, in
# headless Chrome, with the JavaScript copy in browser/app.js (from the
# built static/ site), and compares the HTML.
#
#   bin/build-static && ruby test/layout_parity.rb [SAMPLE_SIZE]
#
# Needs Google Chrome. Exits non-zero if any entry differs.
Encoding.default_external = Encoding::UTF_8
require 'cgi'
require 'json'
require 'open3'
require 'tmpdir'
require_relative '../lib/dictionary'

ROOT = File.expand_path('..', __dir__)
DATA_DIR = File.join(ROOT, 'data')
STATIC = File.join(ROOT, 'static')
CHROME = ENV.fetch('CHROME', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
SAMPLE = (ARGV[0] || 400).to_i

abort 'Build the static site first: bin/build-static' unless File.exist?(File.join(STATIC, 'data.js'))
abort "Chrome not found at #{CHROME} (set CHROME)" unless File.exist?(CHROME)

dict = Dictionary.load(DATA_DIR)
targets = {}
dict.entries.each { |e| targets[e.xml_id] ||= e.id if e.xml_id }
markup = SourceMarkup.new(targets, SourceMarkup.load_sources(File.join(DATA_DIR, 'sources.json')))

# The same entry text the static build ships (see bin/build-static).
chunks = Dictionary.files(DATA_DIR).flat_map do |file|
  Dictionary.clean(File.read(file)).gsub(/<!--.*?-->/m, '').scan(%r{<entry\b[^>]*>.*?</entry>}m)
end

# Entries we designed with, plus a seeded random sample.
named = ['1 rún', 'foillsigid', 'berraid', 'acarda', 'aithrechad', '1 in', 'cechrad', '4 co', 'ate']
ids = named.filter_map { |o| dict.entries.find { |e| e.orth == o }&.id }
ids |= (1..dict.entries.size).to_a.sample(SAMPLE, random: Random.new(1))

ruby = ids.to_h do |id|
  html = EntryLayout.new(chunks[id - 1], markup: markup).html
  [id, html.gsub('href="/entries/', 'href="#/entries/')] # the static site's links
end

# A copy of the static page that renders the sample and writes it out.
page = File.join(STATIC, "parity-#{Process.pid}.html")
harness = <<~JS
  <script>
  (function wait() {
    if (!window.edilLayout) return setTimeout(wait, 50);
    const out = {};
    for (const id of #{ids.to_json}) out[id] = window.edilLayout(id);
    const pre = document.createElement('pre');
    pre.id = 'parity';
    pre.textContent = JSON.stringify(out);
    document.body.appendChild(pre);
  })();
  </script>
JS
File.write(page, File.read(File.join(STATIC, 'index.html')).sub('</body>', "#{harness}</body>"))
begin
  dom = Dir.mktmpdir do |profile|
    out, = Open3.capture2(CHROME, '--headless=new', "--user-data-dir=#{profile}", '--disable-gpu',
                          '--virtual-time-budget=60000', '--dump-dom', "file://#{page}", err: File::NULL)
    out
  end
ensure
  File.delete(page)
end

json = dom[%r{<pre id="parity">(.*?)</pre>}m, 1] or abort 'The page did not produce results (did data.js load?)'
js = JSON.parse(CGI.unescapeHTML(json)).transform_keys(&:to_i)

diffs = ids.reject { |id| ruby[id] == js[id] }
puts "#{ids.size} entries compared, #{diffs.size} differ"
diffs.first(5).each do |id|
  a = ruby[id]
  b = js[id].to_s
  at = (0...[a.size, b.size].min).find { |i| a[i] != b[i] } || [a.size, b.size].min
  puts "\n##{id} #{dict.entry(id).label}: first difference at character #{at}"
  puts "  ruby: …#{a[[at - 60, 0].max, 140]}"
  puts "  js:   …#{b[[at - 60, 0].max, 140]}"
end
exit(diffs.empty? ? 0 : 1)
