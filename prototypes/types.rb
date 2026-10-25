# Renders one example of each word type in layout A, plus the shortest and
# longest entries, each beside today's rendering.
#
#   ruby prototypes/types.rb  -> prototypes/types.html, prototypes/longest.html
Encoding.default_external = Encoding::UTF_8
require_relative 'layout_a'
require_relative 'see_also'
require_relative 'page'

DATA_DIR = File.join(__dir__, '..', 'data')

Candidate = Struct.new(:entry, :labels) do
  def id = entry.id
  def section = entry.section
  def xml = entry.xml
  def orth = entry.orth
  def code = entry.code
  def size = xml.size
  def doubtful? = orth.start_with?('?')
end

# Word types: the editors' code (<pos value="n">) or, in entries without
# one, the printed label (<pos>prep.</pos>).
TYPES = [
  ['Noun', ->(c) { c.code == 'n' }],
  ['Adjective', ->(c) { c.code == 'adj' }],
  ['Verb', ->(c) { c.code == 'v' }],
  ['Verbal noun', ->(c) { c.code.nil? && c.labels.first == 'vn' }],
  ['Proper name', ->(c) { c.code == 'pn' || (c.code.nil? && %w[n.pr npr].include?(c.labels.first)) }],
  ['Pronoun', ->(c) { c.code == 'pron' || (c.code.nil? && c.labels.first == 'pron') }],
  ['Numeral', ->(c) { c.code == 'num' }],
  ['Adverb', ->(c) { c.code == 'adv' || (c.code.nil? && c.labels.first == 'adv') }],
  ['Preposition', ->(c) { c.code == 'prep' || (c.code.nil? && c.labels.first == 'prep') }],
  ['Conjunction', ->(c) { c.code == 'conj' || (c.code.nil? && c.labels.first == 'conj') }],
  ['Particle', ->(c) { %w[part particle].include?(c.code) || (c.code.nil? && c.labels.first == 'particle') }],
  ['Prefix', ->(c) { %w[pref prefix].include?(c.code) || (c.code.nil? && c.labels.first == 'prefix') }],
  ['Interjection', ->(c) { c.code == 'interj' || (c.code.nil? && c.labels.first == 'interj') }],
  ['Article', ->(c) { c.orth == '1 in' }],
  ['Uncertain meaning (code “ind”)', ->(c) { c.code == 'ind' }],
  ['Cross-reference (code “x”)', ->(c) { c.code == 'x' }]
].freeze

INDEX = EntryIndex.new(DATA_DIR)
entries = INDEX.entries.map do |e|
  Candidate.new(e, e.xml.scan(%r{<pos\b[^>]*>([^<]+)</pos>}).flatten.map { |t| t.strip.downcase.chomp('.') })
end

def render_entry(c)
  layout = LayoutA.new(c.xml)
  [layout, layout.html]
end

# Prefers a mid-sized entry with a clear headword that the layout handles
# without flagging anything. Cross-references and uncertain words are short
# by nature, so for those the typical size is used instead.
def choose(list, target)
  ranked = list.reject(&:doubtful?).sort_by { |c| (c.size - target).abs }
  ranked = list.sort_by { |c| (c.size - target).abs } if ranked.empty?
  ranked.first(25).find { |c| render_entry(c).first.issues.empty? } || ranked.first
end

def current_html(xml)
  Markup.new.to_html(Nokogiri::XML(xml).root.children.map { |c| c.to_xml(encoding: 'UTF-8') }.join)
end

def section_html(title, why, c)
  layout, html = render_entry(c)
  label = Dictionary.label(c.orth.empty? ? '?' : c.orth)
  issues = layout.issues.empty? ? '' : %(<p class="meta">Flagged: #{CGI.escapeHTML(layout.issues.map(&:first).tally.map { |k, n| "#{k} ×#{n}" }.join(', '))}</p>)
  <<~HTML
    <section id="#{title.downcase.gsub(/[^a-z]+/, '-')}"><h2>#{CGI.escapeHTML(title)}</h2>
    <p class="why">#{why}</p>
    <p class="meta">Entry #{c.id} · #{c.section} · #{c.size} characters of XML · #{layout.lines} lines</p>
    #{issues}
    <div class="headword">#{CGI.escapeHTML(label)}</div>
    <div class="layout-a">#{html}#{SeeAlso.html(c.entry, INDEX)}</div>
    <details><summary>Today’s rendering</summary><div>#{current_html(c.xml)}</div></details>
    </section>
  HTML
end

sections = []
nav = []
TYPES.each do |name, match|
  list = entries.select { |c| match.call(c) }
  next puts("#{name}: none found") if list.empty?

  target = name =~ /code/ ? list.map(&:size).sort[list.size / 2] : 2500
  c = choose(list, target)
  puts format('%-34s %-18s %6d chars  (%d entries of this type)', name, c.orth, c.size, list.size)
  sections << section_html(name, "#{list.size} entries of this type; this one is ##{c.id}.", c)
  nav << name
end

# More cross-references: one whose target is itself a cross-reference, one
# with several targets, and a "see prec." (the previous entry).
xrefs = entries.select { |c| c.code == 'x' }
chain = xrefs.find do |c|
  t = INDEX.targets_of(c.entry)
  t.size == 1 && t.first.cross_reference? && INDEX.targets_of(t.first).size == 1 &&
    !INDEX.targets_of(t.first).first.cross_reference? && INDEX.targets_of(t.first).first.xml.size.between?(800, 3000)
end
several = xrefs.find { |c| INDEX.targets_of(c.entry).size == 2 && INDEX.targets_of(c.entry).none?(&:cross_reference?) && INDEX.targets_of(c.entry).sum { |t| t.xml.size }.between?(1500, 4000) }
prec = xrefs.find { |c| c.xml.gsub(/<[^>]+>/, ' ') =~ /\bsee\s+prec\b/i && INDEX.targets_of(c.entry).any? }
{ 'Cross-reference to a cross-reference' => chain, 'Cross-reference with two targets' => several,
  'Cross-reference to the previous entry (“see prec.”)' => prec }.each do |name, c|
  next puts("#{name}: none found") unless c

  puts format('%-34s %-18s', name, c.orth)
  sections << section_html(name, "Points to #{INDEX.targets_of(c.entry).map(&:label).join(' and ')}.", c)
  nav << name
end

real = entries.reject { |c| c.orth.empty? }
shortest = real.min_by(&:size)
longest = real.max_by(&:size)
empty = entries.count { |c| c.orth.empty? }
sections << section_html('Shortest entry', "The shortest entry with a headword#{empty.positive? ? " (#{empty} entries have no headword at all)" : ''}.", shortest)
nav << 'Shortest entry'
puts "Shortest: #{shortest.orth} (#{shortest.size}); longest: #{longest.orth} (#{longest.size})"

index = nav.map { |n| %(<a href="##{n.downcase.gsub(/[^a-z]+/, '-')}">#{CGI.escapeHTML(n)}</a>) }.join(' · ')
intro = <<~HTML
  <section><h2>Layout A by word type</h2>
  <p>#{index} · <a href="longest.html">Longest entry (separate page)</a></p></section>
HTML
File.write(File.join(__dir__, 'types.html'), Page.html('Layout A by word type', intro + sections.join("\n")))
File.write(File.join(__dir__, 'longest.html'),
           Page.html("Longest entry: #{longest.orth}",
                     section_html('Longest entry', 'The longest entry in the dictionary, on its own page because of its size.', longest)))
puts 'Wrote prototypes/types.html and prototypes/longest.html'
