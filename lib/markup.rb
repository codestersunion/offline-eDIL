# Converts the dictionary's XML markup into HTML.
#
# Every XML element becomes a <span> whose class is the element name, so the
# stylesheet can style the TEI vocabulary directly (.orth, .def, .bibl, ...).
# Cross-references whose target is a known headword become links.
#
# The same tokenizer also splits the text into the printed edition's
# column/line units, marked in the source by <br column="x" line="y"/>.
# Elements regularly span line breaks, so each line closes the elements still
# open at its end and the next line reopens them.
class Markup
  TOKEN = /<!--.*?-->|<\?.*?\?>|<!DOCTYPE[^>]*>|<[^>]+>|[^<]+/m
  ATTR  = /([\w:.-]+)="([^"]*)"/
  # Elements rendered with a native HTML tag rather than a span.
  NATIVE = { 'sup' => 'sup', 'b' => 'b' }.freeze
  # Wrapper elements that carry no meaning for display.
  SKIP = %w[sample].freeze

  Line = Struct.new(:column, :number, :html)

  def initialize(link_targets = {})
    @link_targets = link_targets
  end

  # HTML for a balanced XML fragment; line-break markers are dropped.
  def to_html(xml)
    out = +''
    walk(xml) { |kind, html| out << html unless kind == :br }
    out
  end

  # Splits a whole document into Line structs in reading order.
  def lines(xml)
    lines = []
    current = nil
    stack = []
    walk(xml, stack) do |kind, html, attrs|
      if kind == :br
        if current
          current.html << stack.reverse.map(&:last).join
          lines << current
        end
        current = Line.new(attrs['column'].to_i, attrs['line'].to_i, stack.map { |s| s[1] }.join)
      elsif current
        current.html << html
      end
    end
    if current
      current.html << stack.reverse.map(&:last).join
      lines << current
    end
    lines
  end

  private

  # Yields [kind, html, attrs] for each token. `stack` holds
  # [name, open_html, close_html] for the elements currently open.
  def walk(xml, stack = [])
    xml.scan(TOKEN) do |tok|
      if tok.start_with?('<!--', '<?', '<!')
        next
      elsif tok.start_with?('</')
        name = tok[2..].strip.chomp('>').strip
        idx = stack.rindex { |s| s[0] == name }
        next unless idx
        closing = stack.slice!(idx..).reverse.map(&:last).join
        yield :close, closing, nil
      elsif tok.start_with?('<')
        self_closing = tok.end_with?('/>')
        name = tok[/\A<([\w:.-]+)/, 1] or next
        attrs = tok.scan(ATTR).to_h
        if name == 'br' && attrs['column']
          yield :br, '', attrs
          next
        end
        open, close = tags_for(name, attrs)
        if self_closing
          yield :empty, open + close, attrs
        else
          stack << [name, open, close]
          yield :open, open, attrs
        end
      else
        yield :text, tok, nil
      end
    end
  end

  def tags_for(name, attrs)
    return ['', ''] if SKIP.include?(name) || name == 'br'
    return ["<#{NATIVE[name]}>", "</#{NATIVE[name]}>"] if NATIVE[name]

    if %w[ref xref].include?(name) && (id = @link_targets[attrs['target']])
      return [%(<a class="#{name}" href="/entries/#{id}">), '</a>']
    end

    extra = attrs['lang'] ? %( lang="#{attrs['lang'].downcase}") : ''
    [%(<span class="#{name}"#{extra}>), '</span>']
  end
end
