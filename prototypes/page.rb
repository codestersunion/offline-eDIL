# A standalone HTML page for the prototypes, with the app's dictionary
# colours (public/css/edil.css) and layout A's styles inlined.
require 'cgi'

module Page
  APP_CSS = File.read(File.join(__dir__, '..', 'public', 'css', 'edil.css'))
                .sub(/@font-face[^}]*\}/, '').sub(/body \{[^}]*\}/, '')
  LAYOUT_CSS = File.read(File.join(__dir__, '..', 'public', 'css', 'entry.css')) +
               # Survey pages: lines the checks flagged.
               ".layout-a .flagged { background: #fff1f0; box-shadow: inset 3px 0 0 #e0796b; }\n"

  BASE_CSS = <<~CSS
    body { margin: 0; background: #EEE; color: #333; font: 15px/1.6 "Helvetica Neue", Helvetica, Arial, sans-serif; }
    a { color: #08c; }
    .wrap { max-width: 1000px; margin: 0 auto; padding: 16px; }
    section { background: #fff; border-radius: 6px; padding: 8px 28px 20px; margin: 16px 0 28px; }
    section > h2 { margin-bottom: 0; font-size: 1.1em; color: #888; }
    section > p.why { color: #888; margin-top: 2px; font-size: 0.9em; }
    .headword { font-size: 1.8em; font-weight: bold; letter-spacing: 0.03em; margin: 14px 0 4px; }
    .meta { color: #999; font-size: 0.85em; }
    details { margin-top: 14px; border-top: 1px solid #eee; padding-top: 8px; }
    details > summary { color: #888; cursor: pointer; }
    details > div { font-size: 14px; margin-top: 8px; }
    table.summary { border-collapse: collapse; }
    table.summary td, table.summary th { padding: 3px 14px 3px 0; text-align: left; vertical-align: top; }
    table.summary td.n { text-align: right; font-variant-numeric: tabular-nums; }
  CSS

  def self.html(title, body)
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{CGI.escapeHTML(title)}</title>
      <style>#{BASE_CSS}#{APP_CSS}#{LAYOUT_CSS}</style>
      </head>
      <body><div class="wrap">
      #{body}
      </div></body>
      </html>
    HTML
  end
end
