# Renders one entry in layout A next to today's rendering.
#
#   ruby prototypes/formats.rb [prototypes/run-1.xml]  -> prototypes/run-1.html
Encoding.default_external = Encoding::UTF_8
require_relative 'layout_a'
require_relative 'page'

SRC = ARGV[0] || File.join(__dir__, 'run-1.xml')
OUT = SRC.sub(/\.xml\z/, '.html')

xml = Dictionary.clean(File.read(SRC))
layout = LayoutA.new(xml)
label = Dictionary.label(layout.entry.at('orth').text)
current = Markup.new.to_html(Nokogiri::XML(xml).root.children.map { |c| c.to_xml(encoding: 'UTF-8') }.join)

File.write(OUT, Page.html("Entry format: #{label}", <<~HTML))
  <section><h2>A. One line per form / example</h2>
  <div class="headword">#{CGI.escapeHTML(label)}</div><div class="layout-a">#{layout.html}</div></section>
  <section><h2>Current</h2>
  <div class="headword">#{CGI.escapeHTML(label)}</div>#{current}</section>
HTML
puts "Wrote #{OUT} (#{layout.lines} lines; issues: #{layout.issues.map(&:first).tally.inspect})"
