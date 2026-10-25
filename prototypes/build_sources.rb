# Builds data/sources.json, the full titles behind the dictionary's source
# abbreviations, from eDIL's own bibliography pages as archived by the
# Internet Archive (www.dil.ie/bibliography/<key>, one page per source).
#
#   ruby prototypes/build_sources.rb DIR_OF_DOWNLOADED_PAGES
#
# Each page is a small table of fields: Title, Author/Editor..., Publisher,
# Date, and unlabelled extras such as volume numbers.
Encoding.default_external = Encoding::UTF_8
require 'json'
require 'nokogiri'
require 'uri'

dir = ARGV.fetch(0)
out = File.join(__dir__, '..', 'data', 'sources.json')

# Contributors worth naming in a hover; other fields (notes, editions,
# subjects) are catalogue detail.
ROLES = %w[Author Editor Translator Compiler].freeze

# Words in catalogue names that are titles or roles, not names.
NOT_NAMES = %w[Rev. SJ OFM Hon. Bp. Bishop Mr. Dr. Sir MRIA fl. c. M.A. Ph.D. D.Litt. LL.D.].freeze

# Catalogue names are "Surname, Given names, extras...": keep the surname
# and the given names, dropping dates, titles and notes.
#   "Bergin, Osborn, 1873-1950"                 -> "Osborn Bergin"
#   "Best, R. I. (Richard Irvine)"              -> "R. I. Best"
#   "Bedell, William, 1571-1642, Bp. of Kilmore" -> "William Bedell"
#   "Oengus, the Culdee"                         -> "Oengus the Culdee"
def person(name)
  parts = name.gsub(/\([^)]*\)?/, ' ').delete(')').split(/,[[:space:]]*/).map(&:strip)
  # A few records give dates first and the name in natural order:
  # "1870-85, Henri Gaidoz".
  return parts[1..].join(', ') if parts.first.match?(/\A[\d–-]+\z/) && parts.size > 1

  last, given = parts
  words = given.to_s.split.take_while { |w| w !~ /\d/ }.reject { |w| NOT_NAMES.include?(w) }
  return last if words.empty?
  # An epithet ("the Culdee", "King of Cashel") follows the name.
  return "#{last} #{words.join(' ')}" if words.any? { |w| %w[of the].include?(w) }

  "#{words.join(' ')} #{last}"
end

sources = {}
Dir[File.join(dir, '*.html')].sort.each do |file|
  key = URI.decode_www_form_component(File.basename(file, '.html'))
  doc = Nokogiri::HTML(File.read(file))
  # Some archived pages repeat the record, hence uniq.
  fields = doc.css('tr').map { |tr| tr.css('td').map { |td| td.text.gsub(/\s+/, ' ').strip } }
                .select { |f| f.size == 2 && !f[1].empty? }.uniq
  title = fields.find { |label, _| label == 'Title' }&.last
  unless title
    # Some sources have only a one-line description instead of a record:
    # "O'C. = O'Curry's law transcripts in RIA".
    text = doc.text.gsub(/\s+/, ' ').strip
    next if text.empty? || text.size > 300 || doc.at('td') # a partial record, not a description

    sources[key] = { 'title' => text.sub(/\A[^=]{1,40}=\s*/, '') }
    next
  end

  people = fields.select { |label, _| ROLES.include?(label) }.map { |role, name| [role, person(name)] }.uniq
  sources[key] = {
    'title' => title.sub(%r{\s+/\s.*\z}, '').sub(/\.+\z/, ''), # drop "/ ed. for the first time ..."
    'people' => people,
    'publisher' => fields.find { |label, _| label == 'Publisher' }&.last,
    'date' => fields.find { |label, _| label == 'Date' }&.last,
    # Unlabelled rows hold volume numbers ("I-V", "IV.2") or page counts
    # ("liii, 596"); keep only volume numbers.
    'volumes' => fields.find { |label, value| label.empty? && value.match?(/\A[IVXLC]+(?:[-–.][IVXLC\d]+)*\z/) }&.last
  }.compact
end

File.write(out, JSON.pretty_generate(sources.sort.to_h))
puts "Wrote #{out} (#{sources.size} sources)"
