Encoding.default_external = Encoding::UTF_8

require 'sinatra'
require 'json'
require_relative 'lib/dictionary'

set :server, 'webrick'
set :port, ENV.fetch('PORT', 4567).to_i

DATA_DIR = ENV.fetch('EDIL_DATA', File.join(__dir__, 'data'))
started = Time.now
puts 'Loading dictionary (the first run parses all XML and takes a minute)...'
DICT = Dictionary.load(DATA_DIR)
warn format('Loaded %d entries in %d sections from %s (%.1fs)',
            DICT.entries.size, DICT.sections.size, DATA_DIR, Time.now - started)

helpers do
  def h(text) = Rack::Utils.escape_html(text.to_s)
  def entry_path(e) = "/entries/#{e.id}"
  def column_path(section, column) = "/columns/#{Rack::Utils.escape_path(section)}/#{column}"
end

get '/' do
  section = DICT.sections.keys.first
  redirect column_path(section, DICT.columns(section).first)
end

get '/browse' do
  redirect '/columns'
end

get '/columns' do
  # First headword in each column, as a label for the index.
  @first_entry = {}
  DICT.entries.each { |e| @first_entry[[e.section, e.column]] ||= e if e.column }
  erb :columns
end

# A page of the printed dictionary: an odd-numbered column and the one after it.
get '/columns/:section/:number' do
  @section = params[:section]
  columns = DICT.columns(@section)
  n = params[:number].to_i
  halt 404, erb(:not_found) unless columns.include?(n)
  n -= 1 if n.even? && columns.include?(n - 1)
  @left = n
  @right = columns.include?(n + 1) ? n + 1 : nil
  sections = DICT.sections.keys
  idx = sections.index(@section)
  @prev = if columns.include?(n - 2) then [@section, n - 2]
          elsif idx.positive? then (s = sections[idx - 1]) && [s, DICT.columns(s)[-1].then { |c| c.even? ? c - 1 : c }]
          end
  @next = if columns.include?(n + 2) then [@section, n + 2]
          elsif (s = sections[idx + 1]) then [s, DICT.columns(s).first]
          end
  @progress = ((columns.index(@right || @left) + 1) * 100.0 / columns.size).round
  @highlight = params[:line] && "c#{params[:number].to_i}l#{params[:line].to_i}"
  erb :column
end

get '/entries' do
  @section = DICT.sections.key?(params[:section]) ? params[:section] : DICT.sections.keys.first
  @entries = DICT.entries.select { |e| e.section == @section }
  erb :entries
end

get '/entries/:id' do
  @entry = DICT.entry(params[:id]) or halt 404, erb(:not_found)
  @prev = DICT.entry(@entry.id - 1)
  @next = DICT.entry(@entry.id + 1)
  erb :entry
end

get '/search' do
  @query = params[:q].to_s.strip
  @in = params[:in] == 'definitions' ? 'definitions' : 'headwords'
  @results = @in == 'definitions' ? DICT.search_definitions(@query) : DICT.search(@query)
  exact = @results.select { |e| e.key == Dictionary.headword_key(@query) }
  redirect entry_path(exact.first) if @in == 'headwords' && exact.size == 1
  erb :search
end

get '/headwords.json' do
  content_type :json
  # [label, normalized key, entry id] for the navbar typeahead.
  DICT.entries.map { |e| [e.label, e.key, e.id] }.to_json
end

get '/bibliography' do
  @sources = DICT.sources.sort_by { |title, _| Dictionary.normalize(title) }
  erb :bibliography
end

get '/bibliography/:title' do
  @title = params[:title]
  @entries = DICT.sources.fetch(@title) { halt 404, erb(:not_found) }
  erb :source
end

get '/about' do
  erb :about
end

get '/contact' do
  erb :contact
end

not_found do
  erb :not_found
end
