# Lays out a dictionary entry for reading ("layout A"): one line per
# grammatical form and per example, references inline. Nothing is
# reworded or reordered; the entry only gains line breaks and structure.
#
# The entry is split into display units from its markup:
# - grammar paragraphs (<form><p>): a header line, then a row per run of
#   grammatical labels (ns., fut. 1 s. ...) and per form, as a table
# - other paragraphs: an intro line ((a) + definitions), notes ("Of profane
#   mysteries:") and citations (Irish quotation + translation + references)
#
# browser/app.js has a JavaScript copy of these rules for the browser-only
# build; test/layout_parity.rb checks the two produce the same HTML.
#
# With `annotate: true` it also records `issues` (text changed, lines that
# probably hold two examples ...) and flags those lines in the HTML, for
# checking the rules against the whole dictionary (prototypes/survey.rb).
require 'cgi'
require 'nokogiri'
require_relative 'source_markup'

class EntryLayout
  # Grammatical labels that head a new line rather than continue an example.
  LABELS = %w[case number gram].freeze
  # In a grammar paragraph, a run of these labels heads a row: "gs.",
  # "fut. 1 s.", "3 s. perf.", "pass. s.".
  FORM_LABELS = %w[case number per tns mood voice].freeze
  # A citation ends at the first full stop that is followed by the end of the
  # text, a capital or a "?" (the source's mark of a doubtful example), so
  # abbreviations like "O'Cl. (an inference)" stay inside it.
  BOUNDARY = /[.;](?=\s*(?:\z|\p{Lu}|\?))/
  LONG_LINE = 400

  def self.paren_delta(text) = text.count('(') - text.count(')')

  def self.blank?(node) = node.text? && node.text.strip.empty?

  def self.letters(text) = text.gsub(/[^\p{L}\p{N}]/, '')

  # A node as XML, exactly as written: Nokogiri's default output is
  # pretty-printed, which adds whitespace the source doesn't have.
  def self.to_xml(node) = node.to_xml(encoding: 'UTF-8', save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)

  # A row of the grammar table. `kind` is :head (text before the first
  # label), :row (labels + what follows) or :more (a further form or note
  # without labels).
  Row = Struct.new(:kind, :label, :nodes, :closed) do
    def refs? = nodes.any? { |n| n.element? && n.name == 'bibl' }

    def form? = nodes.any? { |n| n.element? && %w[oVar q].include?(n.name) }

    def empty? = nodes.all? { |n| EntryLayout.blank?(n) }
  end

  Unit = Struct.new(:type, :nodes, :closed) do
    def refs? = nodes.any? { |n| n.element? && n.name == 'bibl' }

    # Ends with a reference, optionally followed by a comma.
    def after_reference?
      last, before = nodes.reject { |n| EntryLayout.blank?(n) }.last(2).reverse
      return true if last&.element? && last.name == 'bibl'

      last&.text? && last.text.strip == ',' && before&.element? && before.name == 'bibl'
    end

    def bracket_depth = nodes.select(&:text?).sum { |n| EntryLayout.paren_delta(n.text) }

    # A trailing label such as "cf." introduces what follows, so it moves to
    # the next unit.
    def take_trailing_label
      idx = nodes.rindex { |n| !EntryLayout.blank?(n) }
      return [] unless idx && nodes[idx].element? && nodes[idx].name == 'lbl'

      nodes.slice!(idx..).reject { |n| EntryLayout.blank?(n) }
    end
  end

  attr_reader :entry, :issues, :lines

  # `xml` is one <entry> element of cleaned source text (Dictionary.clean).
  # `markup` renders the elements; a SourceMarkup with the dictionary's
  # cross-reference targets links "see X" and adds source descriptions.
  def initialize(xml, markup: SourceMarkup.new, annotate: false)
    # A hyphen at the end of a printed line ("dis-|pute") is followed by the
    # line marker and a space; close the gap so it reads "dis-pute".
    xml = xml.gsub(/(\p{L})-\s*(<br [^>]*\/>)\s*(?=\p{L})/, '\1-\2')
    @doc = Nokogiri::XML(xml) { |c| c.recover.nonet }
    @entry = @doc.root
    @doc.css('br').remove
    # Shortened references ("12d44") point at the reference that names their
    # source; this maps those ids to the source title ("Wb.").
    @titles = @doc.css('title').each_with_object({}) { |t, h| h[t['xml:id']] = t.text.strip if t['xml:id'] }
    # Let shortened references carry their source's key, for its description.
    source_keys = @doc.css('title').each_with_object({}) { |t, h| h[t['xml:id']] = t['target'] if t['xml:id'] && t['target'] }
    @doc.css('orphanScope').each { |o| (key = source_keys[o['target']]) && o['source'] = key }
    @markup = markup
    @annotate = annotate
    @issues = []
    @lines = 0
  end

  def html
    @html ||= begin
      blocks = blocks_of(@entry)
      # Measured before rendering, which adds source hints to the document.
      if @annotate
        source_text = blocks.map { |_, nodes| nodes.is_a?(Array) ? nodes.map(&:text).join : nodes.text }.join
        entry_text = @entry.text
      end
      out = blocks.map do |kind, nodes|
        case kind
        when :grammar then grammar_html(nodes)
        when :sense then %(<div class="sense-block">#{sense_html(nodes)}</div>)
        else %(<div class="note raw">#{render(nodes)}</div>)
        end
      end.join("\n")
      check_text(source_text, entry_text, out) if @annotate
      out
    end
  end

  private

  def issue(kind, detail = nil) = @issues << [kind, detail]

  # ---- Structure -----------------------------------------------------------

  # [kind, node(s)] for each paragraph to lay out, in document order:
  # :grammar for <form><p>, :sense for other paragraphs, :raw for anything
  # else that has text.
  def blocks_of(node, out = [])
    node.element_children.each do |el|
      case el.name
      when 'form'
        el.element_children.each do |c|
          case c.name
          when 'p' then out << [:grammar, c]
          when 'orth' then next
          else
            out << [:raw, [c]]
            issue(:unexpected_markup, "form > #{c.name}")
          end
        end
      when 'p' then out << [:sense, el]
      when 'sense', 'eg', 'egForm' then blocks_of(el, out)
      else
        out << [:raw, [el]]
        issue(:unexpected_markup, "#{node.name} > #{el.name}")
      end
    end
    out
  end

  # Everything except the headword should appear in the layout, in order:
  # the letters shown (minus the grey source hints) must match the source's.
  def check_text(source_text, entry_text, out)
    shown = Nokogiri::HTML.fragment(out).tap { |f| f.css('.hint').remove }.text
    a = EntryLayout.letters(source_text)
    b = EntryLayout.letters(shown)
    issue(:text_changed, "#{a.size} letters in source, #{b.size} shown") unless a == b

    covered = EntryLayout.letters(@entry.css('orth').map(&:text).join).size + a.size
    total = EntryLayout.letters(entry_text).size
    issue(:text_not_laid_out, "#{total - covered} letters") if covered < total
  end

  # ---- Rendering helpers ---------------------------------------------------

  # Collapses whitespace and removes spaces before punctuation ("13d16 ,",
  # "withe ?" and "( FA"), leaving ".i." ("that is") alone.
  def render(nodes)
    @markup.to_html(nodes.map { |n| EntryLayout.to_xml(n) }.join)
           .gsub(/\s+/, ' ')
           .gsub(%r{ ((?:</[^>]+>)+)}, '\1 ') # move spaces out past closing tags
           .gsub(/\s+(?=[,;:)]|\.(?:\s|<|\z))/, '')
           .gsub(/(?<=[\p{L}>])\s+(?=\?)/, '')
           .gsub(/\(\s+/, '(')
           .tr('`', '‘').gsub(%r{(?<=</span>)\s*'}, '’') # the source's `quoted translation'
           .gsub(/‘((?:<[^>]+>)*)\s+/, '‘\1')
           .strip
  end

  # Grammar headers and notes run abbreviations together ("ā,f.", "o,m.").
  def render_label(nodes) = render(nodes).gsub(/,(?=\p{L}|<)/, ', ')

  def text_node(str) = Nokogiri::XML::Text.new(str, @doc)

  def without_trailing_separators(nodes)
    nodes = nodes.dup
    nodes.pop while nodes.last&.text? && nodes.last.text =~ /\A[\s,.;:]*\z/
    if nodes.last&.text?
      last = nodes.pop
      nodes << text_node(last.text.sub(/[\s,.;:]+\z/, ''))
    end
    nodes
  end

  # Where a line starts with a shortened reference, show its source title in
  # grey ("Wb. 12d44" rather than "12d44").
  def hint_orphans(bibls)
    first = bibls.first
    return unless first && first.at('title').nil?

    target = first.at('orphanScope')&.[]('target')
    title = @titles[target]
    return issue(:unknown_source, target) unless title

    hint = Nokogiri::XML::Node.new('hint', @doc)
    hint.content = "#{title} "
    first.prepend_child(hint)
  end

  # Counts a rendered line. When annotating, flags it when it is
  # suspiciously long or `flags` name a problem found while splitting.
  def line(html, flags = [])
    @lines += 1
    return html unless @annotate

    plain = Nokogiri::HTML.fragment(html).text
    if plain.size > LONG_LINE
      issue(:long_line, plain[0, 80])
      flags += ["long line (#{plain.size} characters)"]
    end
    return html if flags.empty?

    html.sub('class="', %(title="#{CGI.escapeHTML(flags.join('; '))}" class="flagged ))
  end

  # ---- Grammar block -------------------------------------------------------

  # Splits a grammar paragraph into rows without moving anything: the text
  # stays in source order and only gains line breaks.
  # - Text before the first label run is the header ("ā, f. (W. rhin)",
  #   "g (follus) In O.Ir. usually dep., ...").
  # - A run of labels outside brackets starts a row ("ns.", "fut. 1 s.").
  # - A full stop after a reference ends the row, unless another reference
  #   follows ("Wb. 12a10. IT i 123.18."); what comes next is a further row
  #   without labels: another form ("rúun, Wb. 1d8") or a note ("Treated as
  #   compd.,").
  #
  # Labels only start a row at a pause (after a full stop, colon, semicolon,
  # bracket or reference): in running prose ("except int of ns. masc.")
  # they stay in the sentence.
  def grammar_rows(p)
    rows = [Row.new(:head, [], [], false)]
    depth = 0
    carry = nil # punctuation left over from a split, for the next row
    add = lambda do |row|
      row.nodes.unshift(text_node(carry)) if carry
      carry = nil
      rows << row
    end
    p.children.each do |n|
      cur = rows.last
      if n.element? && FORM_LABELS.include?(n.name) && depth.zero?
        if cur.kind == :row && !cur.closed && cur.empty?
          cur.label << n
          next
        elsif cur.closed || at_pause?(cur.nodes)
          add.call(Row.new(:row, [n], [], false))
          next
        end
      end
      next if n.element? && n.name == 'pos' && n.text.strip.empty? # an editor's code, not printed text

      if n.text?
        t = n.text
        if cur.kind == :row && cur.empty? && !cur.closed && t !~ /\p{L}/
          cur.label << n # spacing between labels
          next
        end
        stop = t.to_enum(:scan, BOUNDARY).map { Regexp.last_match.begin(0) }
                .find { |pos| depth + EntryLayout.paren_delta(t[0..pos]) <= 0 }
        depth = [depth + EntryLayout.paren_delta(t), 0].max
        next_el = n.next_element
        if stop && cur.kind != :head && !cur.closed && cur.refs? && next_el&.name != 'bibl'
          cur.nodes << text_node(t[0..stop])
          cur.closed = true
          rest = t[(stop + 1)..].lstrip
          if rest =~ /\p{L}/ then add.call(Row.new(:more, [], [text_node(rest)], false))
          elsif !rest.strip.empty? then carry = rest
          end
          next
        end
      end
      if cur.closed
        add.call(Row.new(:more, [], [n], false)) unless EntryLayout.blank?(n)
      else
        cur.nodes << n
      end
    end
    rows.reject { |r| r.empty? && r.label.empty? }
  end

  # True when `nodes` end at a natural break: nothing yet, a reference, or
  # text ending in . : ; ) ? or ! (a trailing "cf." aside).
  def at_pause?(nodes)
    sig = nodes.reject { |n| EntryLayout.blank?(n) }
    sig.pop while sig.last&.element? && sig.last.name == 'lbl'
    last = sig.last
    return true if last.nil? || (last.element? && last.name == 'bibl')

    last.text.strip.match?(/[.:;)?!]\z/)
  end

  # "(b)" or "b" in bold: the letter of a sense or sub-sense.
  def sense_letter?(node) = node&.element? && node.name == 'b' && node.text.strip.match?(/\A\(?[a-z0-9]{1,4}\)?\z/i)

  def grammar_html(p)
    html = +''
    table = false
    grammar_rows(p).each do |r|
      hint_orphans(r.nodes.select { |n| n.element? && n.name == 'bibl' })
      if r.kind == :head
        html << line(%(<div class="gram-head">#{render_label(r.nodes)}</div>))
        next
      end
      html << '<table class="grammar">' unless table
      table = true
      content = render(without_trailing_separators(r.nodes))
      html << if r.kind == :more && !r.form?
                line(%(<tr><td colspan="2" class="gram-note">#{render_label(r.nodes)}</td></tr>))
              else
                line(%(<tr><td class="gram-label">#{render_label(r.label)}</td><td class="gram-form">#{content}</td></tr>))
              end
    end
    html << '</table>' if table
    html
  end

  # ---- Senses --------------------------------------------------------------

  # Normally only a full stop after a reference ends a citation; one right
  # before a grammatical label ("... O'Cl. (an inference). gs. as attrib.:")
  # or a sense letter ("... Mil 72 c 9. (b) after a noun") counts too. Full
  # stops inside brackets never do.
  def segment(p)
    units = [Unit.new(:intro, [], false)]
    carry = nil # punctuation left over from a split, for the next unit
    add = lambda do |unit|
      unit.nodes.unshift(text_node(carry)) if carry
      carry = nil
      units << unit
    end
    p.children.each do |n|
      cur = units.last
      if n.text?
        t = n.text
        before_heading = (LABELS.include?(n.next_element&.name) && t =~ /[.;]\s*\z/) ||
                         (sense_letter?(n.next_element) && t =~ /[.;]\s*\(?\s*\z/)
        depth = cur.bracket_depth
        i = t.to_enum(:scan, BOUNDARY).map { Regexp.last_match.begin(0) }
             .find { |pos| depth + EntryLayout.paren_delta(t[0..pos]) <= 0 }
        i ||= t.rindex(/[.;]/) if before_heading
        if cur.type == :citation && !cur.closed && (cur.refs? || before_heading) && i
          cur.nodes << text_node(t[0..i])
          cur.closed = true
          rest = t[(i + 1)..].lstrip
          if rest =~ /\p{L}/ then add.call(Unit.new(:note, [text_node(rest)], false))
          elsif !rest.strip.empty? then carry = rest
          end
        elsif cur.closed
          if t =~ /\p{L}/ then add.call(Unit.new(:note, [n], false))
          elsif !t.strip.empty? then carry = "#{carry}#{t}"
          end
        else
          cur.nodes << n
        end
      elsif n.name == 'q' && cur.type != :citation && !cur.closed && !at_pause?(cur.nodes)
        # A form quoted mid-sentence ("The s- does not remain after OC"):
        # the line is prose, not a heading.
        cur.nodes << n
        cur.type = :intro
      elsif n.name == 'q' && (cur.type != :citation || cur.closed)
        label = cur.take_trailing_label
        label << text_node(' ') unless label.empty?
        add.call(Unit.new(:citation, label + [n], false))
      elsif n.name == 'q' && cur.after_reference?
        # A quotation straight after a reference, with no full stop between
        # them (or only a comma), is a new example.
        cur.closed = true
        add.call(Unit.new(:citation, [n], false))
      elsif cur.closed && n.name == 'bibl' && cur.type == :citation && carry.nil?
        # More references after the full stop ("Wb 22 c 9. 26 b 7.") belong
        # to the same example.
        cur.closed = false
        cur.nodes << text_node(' ') << n
      elsif cur.closed
        # A sense letter starts a sense line; a grammatical label or a
        # definition ("Esp. of super-normal revelation:") heads what follows;
        # anything else starts an example.
        type = if sense_letter?(n) then :intro
               elsif LABELS.include?(n.name) || (n.name == 'trans' && n.at('def')) then :note
               else :citation
               end
        add.call(Unit.new(type, [n], false))
      else
        cur.nodes << n
      end
    end
    units.reject { |u| u.nodes.all? { |n| EntryLayout.blank?(n) } }
  end

  def sense_html(p)
    html = +''
    list_open = false
    segment(p).each do |u|
      flags = @annotate ? check_unit(u) : []
      hint_orphans(u.nodes.select { |n| n.element? && n.name == 'bibl' })
      if u.type == :citation
        html << '<ul class="cites">' unless list_open
        list_open = true
        html << line(%(<li class="cite">#{render(u.nodes).sub(/[,;]\z/, '')}</li>), flags)
      else
        html << '</ul>' if list_open
        list_open = false
        html << line(%(<div class="#{u.type}">#{render(u.nodes)}</div>), flags)
      end
    end
    html << '</ul>' if list_open
    html
  end

  # Returns flags for a line that probably holds more than one example (a
  # quotation after a reference and a full stop) or no quotation at all.
  def check_unit(u)
    flags = []
    seen_ref = false
    stop_after_ref = false
    u.nodes.each do |n|
      if n.element? && n.name == 'bibl' then seen_ref = true
      elsif n.text? && seen_ref && n.text =~ /[.;]/ then stop_after_ref = true
      elsif n.element? && n.name == 'q' && stop_after_ref
        issue(:missed_split, n.text.strip[0, 60])
        flags << 'probably two examples'
        break
      end
    end
    if u.type == :citation && u.nodes.none? { |n| n.element? && n.name == 'q' }
      issue(:line_without_quote, Nokogiri::HTML.fragment(render(u.nodes)).text[0, 60])
      flags << 'example line with no Irish quotation'
    end
    flags
  end
end
