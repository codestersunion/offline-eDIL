require 'digest'
require 'fileutils'
require 'nokogiri'
require 'zlib'
require_relative 'markup'
require_relative 'source_markup'
require_relative 'entry_layout'
require_relative 'cross_references'

# Loads the eDIL XML files into memory: entries (with their parts of speech,
# definitions, bibliographic references, laid-out HTML and, for "see X"
# entries, the entries they point to) and the printed column/line text.
#
# Each XML file is a "section" (A, B, ..., D1, D2, ...). Column numbers restart
# in each section, so the printed text is keyed by [section, column].
# Source abbreviations get their full titles from sources.json next to the
# XML files, when present.
#
# Parsing every file takes a while, so the result is cached with Marshal and
# reused until the XML files, sources.json or this code change.
class Dictionary
  # Character entities the source uses without declaring them.
  ENTITIES = {
    'aelig' => 'æ', 'sect' => '§', 'rmacr' => 'r̄', 'fdot' => 'ḟ', 'ccon' => 'ꝯ',
    'aacute' => 'á', 'aacte' => 'á', 'eacute' => 'é', 'iacute' => 'í', 'oacute' => 'ó',
    'uacute' => 'ú', 'Eacute' => 'É', 'Oacute' => 'Ó', 'agrave' => 'à', 'ucirc' => 'û',
    'Auml' => 'Ä', 'amacr' => 'ā', 'omacr' => 'ō', 'macr' => '¯', 'ebreve' => 'ĕ',
    'adot' => 'ȧ', 'edot' => 'ė', 'Sdot' => 'Ṡ', 'dotabove' => '˙', 'lstrok' => 'ł',
    'sup2' => '²', 'supa' => 'ª', 'apos' => "'",
    'rdot' => 'ṙ', 'mdot' => 'ṁ', 'fmacr' => 'f̄'
  }.freeze
  XML_ENTITIES = %w[lt gt amp quot].freeze

  # DIL numbers homographs before the headword ("1 rún", "2 rún") and marks
  # doubtful ones with "?" ("? 1 rac", "5? mes(s)", "2, 3 úaill").
  HOMOGRAPH = /\A(?<doubt>\?\s*)?(?<num>\d+\??(?:,\s*\d+)*)\s+(?<word>.+)\z/
  SUPERSCRIPT = '⁰¹²³⁴⁵⁶⁷⁸⁹'

  # Display form with the homograph number as a superscript: "rún¹".
  def self.label(orth)
    m = HOMOGRAPH.match(orth) or return orth
    num = m[:num].gsub(/\d/) { |d| SUPERSCRIPT[d.to_i] }.delete(' ')
    "#{m[:doubt] ? '? ' : ''}#{m[:word]}#{num}"
  end

  # `code` is the editors' word-type code ("n", "v", "x" for a cross-
  # reference ...). `see_also` lists, for a cross-reference, the entries it
  # points to as [id, nearest] (nearest: matched a headword spelled one
  # letter differently).
  Entry = Struct.new(:id, :xml_id, :orth, :label, :key, :html, :parts_of_speech,
                     :definitions, :definitions_key, :bibls, :section, :column, :line,
                     :code, :see_also, keyword_init: true)
  XrefEntry = Struct.new(:id, :orth, :xml_id, :xml)
  Bibl = Struct.new(:title, :scope)
  Line = Markup::Line

  attr_reader :entries, :sections, :sources

  def self.normalize(str)
    str.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
       .gsub(/[^\p{L}\p{N}]+/, ' ').strip
  end

  # Normalized headword, ignoring homograph numbers ("1 rún", "rún¹") and
  # brackets around optional letters ("mes(s)" matches "mess").
  def self.headword_key(query)
    normalize(query.to_s.delete(SUPERSCRIPT).delete('()').sub(/\A[?\s]*\d+\??(?:,\s*\d+)*\s+/, ''))
  end

  # The XML files in a directory, in dictionary order.
  def self.files(dir)
    files = Dir[File.join(dir, '*.xml')].sort_by { |f| section_sort_key(File.basename(f, '.xml')) }
    raise "No dictionary XML files in #{dir}. Download them with: ruby bin/fetch-data" if files.empty?

    files
  end

  # Source text with the DOCTYPE removed and undeclared entities resolved.
  # A few entities appear double-escaped (&amp;rdot;); decode those too.
  def self.clean(src)
    src.sub(/<!DOCTYPE[^>]*>/, '').gsub(/&(amp;)?(\w+);/) do
      escaped, name = Regexp.last_match(1), Regexp.last_match(2)
      if ENTITIES.key?(name) then ENTITIES[name]
      elsif escaped || XML_ENTITIES.include?(name) then Regexp.last_match(0)
      else "&amp;#{name};"
      end
    end
  end

  def self.load(dir, cache_dir: File.join(dir, '.cache'))
    files = self.files(dir)
    code = Dir[File.join(__dir__, '*.rb')].sort.map { |f| File.read(f) }.join
    sources = File.join(dir, 'sources.json')
    stamp = (files + [sources]).select { |f| File.exist?(f) }.map { |f| [File.basename(f), File.size(f), File.mtime(f).to_i] }
    cache = File.join(cache_dir, "dictionary-#{Digest::SHA256.hexdigest(Marshal.dump([stamp, code]))[0, 16]}.bin")

    return Marshal.load(Zlib.inflate(File.binread(cache))) if File.exist?(cache)

    dict = new(files)
    FileUtils.mkdir_p(cache_dir)
    Dir[File.join(cache_dir, 'dictionary-*.bin')].each { |f| File.delete(f) }
    File.binwrite(cache, Zlib.deflate(Marshal.dump(dict), Zlib::BEST_SPEED))
    dict
  end

  # "D1" sorts after "C" and before "D2"; plain letters sort alphabetically.
  def self.section_sort_key(name) = [name[0], name[1..].to_i]

  def initialize(files)
    @entries = []
    entry_xml = []

    # Pass 1: entries and their metadata, so cross-references can be resolved.
    files.each do |file|
      section = File.basename(file, '.xml')
      doc = Nokogiri::XML(self.class.clean(File.read(file, encoding: 'UTF-8'))) { |c| c.recover.nonet }
      doc.css('entry').each do |node|
        @entries << build_entry(node, @entries.size + 1, section)
        entry_xml << node.children.map { |c| EntryLayout.to_xml(c) }.join
      end
    end

    targets = {}
    @entries.each { |e| targets[e.xml_id] ||= e.id if e.xml_id }
    markup = Markup.new(targets)
    sources = SourceMarkup.load_sources(File.join(File.dirname(files.first), 'sources.json'))
    layout_markup = SourceMarkup.new(targets, sources)
    @entries.each_with_index do |e, i|
      e.html = EntryLayout.new("<entry>#{entry_xml[i]}</entry>", markup: layout_markup).html
    end

    xrefs = CrossReferences.new(@entries.map { |e| XrefEntry.new(e.id, e.orth, e.xml_id, entry_xml[e.id - 1]) })
    @entries.each do |e|
      next unless e.code == 'x'

      e.see_also = xrefs.matches_of(XrefEntry.new(e.id, e.orth, e.xml_id, entry_xml[e.id - 1])).map { |t, nearest| [t.id, nearest] }
    end

    # Pass 2: the printed text, split into columns and lines.
    @sections = {}
    files.each do |file|
      section = File.basename(file, '.xml')
      columns = Hash.new { |h, k| h[k] = [] }
      markup.lines(self.class.clean(File.read(file, encoding: 'UTF-8'))).each { |l| columns[l.column] << l }
      @sections[section] = columns.sort.to_h
    end

    @sources = Hash.new { |h, k| h[k] = [] }
    @entries.each { |e| e.bibls.map(&:title).uniq.each { |t| @sources[t] << e } }
    @sources.default_proc = nil
  end

  def entry(id) = id.to_i.positive? ? @entries[id.to_i - 1] : nil

  def columns(section) = @sections.fetch(section, {}).keys

  def lines(section, column) = @sections.fetch(section, {}).fetch(column, [])

  # Headwords matching the query: exact matches first, then prefix matches.
  def search(query, limit: 200)
    q = self.class.headword_key(query)
    return [] if q.empty?

    exact, prefix = [], []
    @entries.each do |e|
      if e.key == q then exact << e
      elsif e.key.start_with?(q) then prefix << e
      end
    end
    (exact + prefix).first(limit)
  end

  # Entries whose definitions contain the query.
  def search_definitions(query, limit: 200)
    q = self.class.normalize(query)
    return [] if q.empty?

    pattern = /\b#{Regexp.escape(q)}/
    @entries.lazy.select { |e| e.definitions_key.match?(pattern) }.first(limit)
  end

  private

  def squish(text) = text.to_s.gsub(/\s+/, ' ').strip

  def build_entry(node, id, section)
    orth_node = node.at_css('orth')
    orth = node.css('orth').map { |o| squish(o.text) }.reject(&:empty?).first ||
           orth_node&.[]('xml:id') || '?'
    br = node.at_css('br[column]')
    definitions = node.css('def').map { |d| squish(d.text) }.reject(&:empty?)

    Entry.new(
      id: id,
      xml_id: orth_node&.[]('xml:id'),
      orth: orth,
      label: self.class.label(orth),
      key: self.class.headword_key(orth),
      parts_of_speech: node.css('pos').map { |p| p.text.strip.empty? ? p['value'].to_s : squish(p.text) }
                           .reject(&:empty?).uniq,
      definitions: definitions,
      definitions_key: definitions.map { |d| self.class.normalize(d) }.join(' | '),
      bibls: node.css('bibl').map { |b| Bibl.new(squish(b.at_css('title')&.text), squish(b.at_css('biblScope, orphanScope')&.text)) }
                 .reject { |b| b.title.empty? },
      section: section,
      column: br && br['column'].to_i,
      line: br && br['line'].to_i,
      code: node.at_css('pos[value]')&.[]('value')&.strip,
      see_also: []
    )
  end
end
