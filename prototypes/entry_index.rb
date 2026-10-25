# All entries of the dictionary, for prototypes that need to look across
# entries: resolving the target of a cross-reference ("see 2 accarda").
require_relative '../lib/dictionary'
require_relative '../lib/cross_references'

class EntryIndex
  Entry = Struct.new(:id, :section, :xml, :orth, :code) do
    def label = Dictionary.label(orth.empty? ? '?' : orth)
    def xml_id = xml[/<orth[^>]*xml:id="([^"]*)"/, 1]
    def cross_reference? = code == 'x'
  end

  attr_reader :entries

  def initialize(dir)
    @entries = []
    Dictionary.files(dir).each do |file|
      section = File.basename(file, '.xml')
      Dictionary.clean(File.read(file)).gsub(/<!--.*?-->/m, '').scan(%r{<entry\b[^>]*>.*?</entry>}m) do |xml|
        @entries << Entry.new(@entries.size + 1, section, xml,
                              xml[%r{<orth[^>]*>([^<]*)</orth>}, 1].to_s.strip,
                              xml[/<pos\b[^>]*value="([^"]*)"/, 1]&.strip)
      end
    end
    @xrefs = CrossReferences.new(@entries)
  end

  def [](id) = @entries[id - 1]

  def find_orth(orth) = @entries.find { |e| e.orth == orth }

  def matches_of(entry) = @xrefs.matches_of(entry)

  def targets_of(entry) = matches_of(entry).map(&:first)
end
