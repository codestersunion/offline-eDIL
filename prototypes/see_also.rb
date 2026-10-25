# For a cross-reference entry ("accairde see 2 accarda"), renders the entry
# it points to underneath, in layout A. A target that is itself a
# cross-reference is followed in turn, up to three steps.
require 'cgi'
require_relative 'layout_a'
require_relative 'entry_index'

module SeeAlso
  MAX_DEPTH = 3

  def self.html(entry, index, depth = 1, seen = [entry.id])
    return '' unless entry.cross_reference? && depth <= MAX_DEPTH

    matches = index.matches_of(entry).reject { |t, _| seen.include?(t.id) }
    return '' if matches.empty?

    matches.map do |t, nearest|
      body = LayoutA.new(t.xml).html
      nested = html(t, index, depth + 1, seen + [t.id])
      note = nearest ? ' · nearest match: the headword is spelled differently' : ''
      <<~HTML
        <div class="see-also">
          <div class="see-also-head">↳ <span class="see-also-label">#{CGI.escapeHTML(t.label)}</span> <span class="meta">entry #{t.id}#{note}</span></div>
          <div class="see-also-body">#{body}#{nested}</div>
        </div>
      HTML
    end.join
  end
end
