# The prototypes use layout A with checking switched on; the layout itself
# lives in lib/entry_layout.rb.
require_relative '../lib/dictionary'
require_relative '../lib/entry_layout'

class LayoutA < EntryLayout
  MARKUP = SourceMarkup.new

  def initialize(xml) = super(xml, markup: MARKUP, annotate: true)
end
