# Markup that gives each source abbreviation its full reference, shown on
# hover, from data/sources.json (built by prototypes/build_sources.rb from
# eDIL's bibliography):
#   Anecd. -> "Anecdota from Irish manuscripts, ed. Osborn Bergin, R. I.
#              Best, Kuno Meyer et al. (M. Niemeyer, I-V, 1907-1913)"
require 'json'
require 'cgi'
require_relative 'markup'

class SourceMarkup < Markup
  FILE = File.join(__dir__, '..', 'data', 'sources.json')

  ROLE_WORDS = { 'Author' => 'by', 'Editor' => 'ed.', 'Translator' => 'tr.', 'Compiler' => 'comp.' }.freeze

  def self.load_sources(file = FILE)
    return {} unless File.exist?(file)

    JSON.parse(File.read(file, encoding: 'UTF-8'))
  end

  def initialize(link_targets = {}, sources = self.class.load_sources)
    super(link_targets)
    @sources = sources
    @by_lowercase = sources.keys.to_h { |k| [k.downcase, k] }
  end

  # "Anecdota from Irish manuscripts, ed. Osborn Bergin, R. I. Best, Kuno
  # Meyer et al. (M. Niemeyer, I-V, 1907-1913)"; nil for an unknown source.
  # Keys match regardless of case ("ML" and "Ml").
  def description(key)
    s = @sources[key] || @sources[@by_lowercase[key.to_s.downcase]]
    return nil unless s

    text = s['title'].dup
    s['people'].to_a.group_by(&:first).each do |role, people|
      names = people.map(&:last)
      shown = names.size > 3 ? "#{names.first(3).join(', ')} et al." : names.join(', ')
      text << ", #{ROLE_WORDS.fetch(role, role.downcase)} #{shown}"
    end
    details = [s['publisher'], s['volumes'], s['date']].compact.reject(&:empty?)
    text << " (#{details.join(', ')})" unless details.empty?
    text
  end

  # Every source's description, keyed by lowercased key (for the
  # browser-only build, which looks them up the same way).
  def descriptions = @sources.keys.to_h { |k| [k.downcase, description(k)] }

  private

  # The source of a <title> is its target; a shortened reference
  # (<orphanScope>) carries its source in `source`, set by EntryLayout.
  #
  # The description goes in data-source and is shown by CSS (entry.css),
  # not the title attribute: native tooltips are slow and don't appear at
  # all in some embedded browsers or on touch screens. tabindex makes it
  # reachable by keyboard and tap.
  def tags_for(name, attrs)
    open, close = super
    key = case name
          when 'title' then attrs['target']
          when 'orphanScope' then attrs['source']
          end
    desc = key && description(key)
    return [open, close] unless desc

    [open.sub(/\A<span class="/, %(<span data-source="#{CGI.escapeHTML(desc)}" tabindex="0" class="source )), close]
  end
end
