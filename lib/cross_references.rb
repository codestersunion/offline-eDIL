# Resolves cross-reference entries ("accairde see 2 accarda") to the
# entries they point to, so those can be shown underneath.
#
# Entries are anything with id (1-based, in dictionary order), orth,
# xml_id and xml (the entry's source markup). Headwords are compared with
# Dictionary.headword_key.
class CrossReferences
  def initialize(entries)
    @entries = entries
    @by_id = entries.group_by(&:xml_id)
    # Headwords with optional letters ("at-bail(l)") are indexed under both
    # readings, so "see at-bail" finds them.
    @by_key = Hash.new { |h, k| h[k] = [] }
    entries.each do |e|
      [e.orth, e.orth.gsub(/\([^)]*\)/, '')].map { |o| Dictionary.headword_key(o) }.uniq.each { |k| @by_key[k] << e }
    end
  end

  # The entries `entry` points to, in order, at most four, as [entry,
  # nearest] pairs. Targets come from <ref target="...">, matched by
  # headword id and then by headword (all homographs); then the
  # reference's visible text; then the word after "see". "see prec." and
  # "see follg." mean the neighbouring entries. `nearest` is true when no
  # headword matched and the only headword one letter away was taken
  # instead ("see anfobrachta" -> anfobracht).
  def matches_of(entry)
    refs = entry.xml.scan(%r{<ref\b[^>]*target="([^"]*)"[^>]*>(.*?)</ref>}m)
    targets = refs.map(&:first)
    text = entry.xml.gsub(/<br [^>]*\/>/, '').gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ')
    see_word = text[/\bsee\s+([^\s.,;]+)/i, 1]
    if targets.empty?
      if text =~ /\bsee\s+prec\b/i then return pairs([entry.id > 1 ? @entries[entry.id - 2] : nil], entry)
      elsif text =~ /\bsee\s+follg\b/i then return pairs([@entries[entry.id]], entry)
      end
    end
    [targets, refs.map { |_, shown| shown.gsub(/<[^>]+>/, '').strip }, [see_word].compact].each do |words|
      found = words.flat_map { |t| resolve(t) }
      return pairs(found, entry) unless found.empty?
    end
    targets = [see_word].compact if targets.empty?
    pairs(targets.flat_map { |t| nearest(t) }, entry, nearest: true)
  end

  private

  def pairs(list, entry, nearest: false)
    list.compact.uniq(&:id).reject { |e| e.id == entry.id }.first(4).map { |e| [e, nearest] }
  end

  def resolve(target)
    exact = @by_id[target]
    return exact if exact

    @by_key.fetch(Dictionary.headword_key(target), [])
  end

  # The headword one letter away from `target` (an added, dropped or
  # changed letter), if there is exactly one such headword.
  def nearest(target)
    key = Dictionary.headword_key(target)
    return [] if key.size < 5

    candidates = @by_key.keys.select { |k| (k.size - key.size).abs <= 1 && k[0, 2] == key[0, 2] && one_edit?(k, key) }
    candidates.size == 1 ? @by_key[candidates.first] : []
  end

  def one_edit?(a, b)
    return false if a == b

    a, b = b, a if a.size > b.size
    i = 0
    i += 1 while i < a.size && a[i] == b[i]
    a.size == b.size ? a[(i + 1)..] == b[(i + 1)..] : a[i..] == b[(i + 1)..]
  end
end
