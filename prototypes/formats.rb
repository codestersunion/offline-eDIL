# Renders one entry in layout A next to today's rendering.
#
#   ruby prototypes/formats.rb ["1 rún"]  -> prototypes/run-1.html
#
# The argument is the headword as it appears in the XML (homograph number
# first); the entry is read from data/ (see bin/fetch-data).
Encoding.default_external = Encoding::UTF_8
require_relative 'layout_a'
require_relative 'entry_index'
require_relative 'page'

orth = ARGV[0] || '1 rún'
entry = EntryIndex.new(File.join(__dir__, '..', 'data')).find_orth(orth) or abort "No entry with headword #{orth.inspect}"
slug = Dictionary.normalize(orth).split.rotate(orth.match?(/\A\d/) ? 1 : 0).join('-') # "1 rún" -> "run-1"
out = File.join(__dir__, "#{slug}.html")

layout = LayoutA.new(entry.xml)
current = Markup.new.to_html(Nokogiri::XML(entry.xml).root.children.map { |c| EntryLayout.to_xml(c) }.join)

File.write(out, Page.html("Entry format: #{entry.label}", <<~HTML))
  <section><h2>A. One line per form / example</h2>
  <div class="headword">#{CGI.escapeHTML(entry.label)}</div><div class="layout-a">#{layout.html}</div></section>
  <section><h2>Current</h2>
  <div class="headword">#{CGI.escapeHTML(entry.label)}</div>#{current}</section>
HTML
puts "Wrote #{out} (#{layout.lines} lines; issues: #{layout.issues.map(&:first).tally.inspect})"
