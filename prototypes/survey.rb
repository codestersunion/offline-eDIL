# Runs layout A over every entry, tallies the problems it finds, and writes
# a sample page: typical short, medium and long entries plus the worst
# examples of each problem, each beside today's rendering.
#
#   ruby prototypes/survey.rb  -> prototypes/survey.html
Encoding.default_external = Encoding::UTF_8
require 'json'
require_relative 'layout_a'
require_relative 'page'

DATA_DIR = File.join(__dir__, '..', 'data')
OUT = File.join(__dir__, 'survey.html')

ISSUES = {
  text_changed: 'Text changed: the letters shown differ from the source',
  text_not_laid_out: 'Text missing: part of the entry is not in the layout',
  missed_split: 'Probably two examples on one line',
  long_line: "Very long line (over #{LayoutA::LONG_LINE} characters)",
  line_without_quote: 'Example line with no Irish quotation',
  unknown_source: 'Shortened reference whose source could not be found',
  unexpected_markup: 'Markup the layout does not expect',
  error: 'Layout raised an error'
}.freeze

Row = Struct.new(:id, :section, :label, :xml, :size, :lines, :issues)

rows = []
Dictionary.files(DATA_DIR).each do |file|
  section = File.basename(file, '.xml')
  text = Dictionary.clean(File.read(file)).gsub(/<!--.*?-->/m, '')
  text.scan(%r{<entry\b[^>]*>.*?</entry>}m) do |chunk|
    id = rows.size + 1
    orth = chunk[%r{<orth[^>]*>([^<]*)</orth>}, 1].to_s.strip
    begin
      layout = LayoutA.new(chunk)
      layout.html
      rows << Row.new(id, section, Dictionary.label(orth.empty? ? '?' : orth), chunk, chunk.size, layout.lines, layout.issues)
    rescue StandardError => e
      rows << Row.new(id, section, orth, chunk, chunk.size, 0, [[:error, "#{e.class}: #{e.message}"[0, 120]]])
    end
  end
end

total = rows.size
affected = ISSUES.keys.to_h { |k| [k, rows.select { |r| r.issues.any? { |i, _| i == k } }] }
clean = rows.count { |r| r.issues.empty? }

puts "#{total} entries, #{clean} with no issues (#{(clean * 100.0 / total).round(1)}%)"
ISSUES.each_key { |k| puts format('  %-20s %6d entries  %7d times', k, affected[k].size, rows.sum { |r| r.issues.count { |i, _| i == k } }) }

# ---- Sample ----------------------------------------------------------------

rng = Random.new(2026)
pick = ->(list, n) { list.sample(n, random: rng) }
by_size = rows.sort_by(&:size)
sample = []
add = ->(why, list) { list.each { |r| sample << [why, r] unless sample.any? { |_, s| s.id == r.id } } }

add.call('Reference: the entry we designed with', rows.select { |r| r.label == 'rún¹' })
add.call('Short entry', pick.call(rows.select { |r| r.size.between?(150, 400) }, 3))
add.call('Typical entry', pick.call(rows.select { |r| r.size.between?(800, 2500) }, 3))
add.call('Long entry', pick.call(rows.select { |r| r.size.between?(12_000, 30_000) }, 2))
ISSUES.each_key do |k|
  # The smallest affected entries show a problem most plainly.
  add.call(ISSUES[k], affected[k].sort_by(&:size).first(2))
end

def current_html(xml)
  Markup.new.to_html(Nokogiri::XML(xml).root.children.map { |c| c.to_xml(encoding: 'UTF-8') }.join)
end

def issue_list(row)
  return '<span class="meta">No issues found.</span>' if row.issues.empty?

  items = row.issues.group_by(&:first).map do |k, list|
    details = list.map(&:last).compact.uniq.first(2).map { |d| "“#{CGI.escapeHTML(d.to_s)}”" }.join(', ')
    "<li>#{CGI.escapeHTML(ISSUES[k] || k.to_s)}#{list.size > 1 ? " (×#{list.size})" : ''}#{details.empty? ? '' : ": #{details}"}</li>"
  end
  %(<ul class="meta">#{items.join}</ul>)
end

summary_rows = ISSUES.map do |k, desc|
  n = affected[k].size
  %(<tr><td>#{CGI.escapeHTML(desc)}</td><td class="n">#{n}</td><td class="n">#{(n * 100.0 / total).round(2)}%</td></tr>)
end.join

largest = by_size.last
body = +<<~HTML
  <section><h2>Layout A across the dictionary</h2>
  <p>#{total} entries; <strong>#{clean}</strong> (#{(clean * 100.0 / total).round(1)}%) pass every check.
  Red-tinted lines below are the ones a check flagged; hover for the reason.</p>
  <table class="summary"><tr><th>Check</th><th>Entries</th><th></th></tr>#{summary_rows}</table>
  <p class="meta">Largest entry: #{CGI.escapeHTML(largest.label)} (#{largest.section}, #{largest.size / 1000} k characters), not shown.</p>
  </section>
HTML

sample.each do |why, r|
  layout = LayoutA.new(r.xml)
  body << <<~HTML
    <section><h2>#{CGI.escapeHTML(why)}</h2>
    <p class="meta">Entry #{r.id} · #{r.section} · #{r.size} characters of XML · #{r.lines} lines</p>
    #{issue_list(r)}
    <div class="headword">#{CGI.escapeHTML(r.label)}</div>
    <div class="layout-a">#{layout.html}</div>
    <details><summary>Today’s rendering</summary><div>#{current_html(r.xml)}</div></details>
    </section>
  HTML
end

File.write(OUT, Page.html('Layout A: survey', body))
File.write(File.join(__dir__, 'survey.json'),
           JSON.pretty_generate(ISSUES.keys.to_h { |k| [k, affected[k].map { |r| [r.id, r.label, r.issues.select { |i, _| i == k }.map(&:last).first(3)] }] }))
puts "Wrote #{OUT} (#{sample.size} sample entries) and survey.json"
