require 'yaml'
require 'json'
require 'open-uri'
require 'ostruct'
require 'pathname'
require 'pdf-reader'
require 'pry'

#TODO: package separately for visualization strategy
require 'graphviz'
require 'optparse'
require 'hirb'
srand(0)

$cli_options = {"display" => 'PrintAll', "block-size"=>1000, "min-match-count"=>2} #.with_indifferent_access

OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby word_histograms.rb [-v] [-o PrintAll|WordGraph] path/to/file_with_pdf_links.txt keywords.yaml"

  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    $cli_options["verbose"] = v
  end

  opts.on("-o", "--display DISPLAY", "display") do |d|
    $cli_options["display"] = d
  end

  opts.on("-m", "--min-match-count MIN_MATCH_COUNT", Integer, "min match count") do |m|
    $cli_options["min-match-count"] = m
  end

  opts.on("-C", "--config-path CONFIG_PATH", "yaml file path relative to root") do |c|
    $cli_options["config-path"] = c
  end

  opts.on("-b", "--block-size BLOCK_SIZE", Integer, "size of the text blocks tested for word variations") do |b|
    $cli_options["block-size"] = b
  end
end.parse!


class WordHistograms

  class WordGraph < Proc
    def self.new(*)
      super() do |io, hits, opts|  
        output_filename = "#{$cli_options["block-size"]}.dot"
        nodes = {} 
        
 
        GraphViz::new( :G, type: :digraph, rankdir: :LR ) { |g|
          
          add_row = lambda do |k,desc|
            _str = ""
            _str += "<TR>"
            _str += "<TD>#{k}</TD>"
            _str += "<TD>#{desc}</TD>"
            _str += "</TR>"
          end
          ensure_node = lambda do |k,hit_count = 0, opts={}|
            if hit_count.nil?
              hit_count = hits[k]
            end
            nodes[k] ||= g.send(k.to_sym, opts.merge(label: "<<TABLE color='red'>#{add_row.call(k,hit_count)}</TABLE>>"))
          end
=begin        
          str = ""
          area.config.send(:hash).each do |k,(default,desc)|
            str += add_option_row.call(k,default,desc)
          end
          a_node = g.send(:area, :label => (str.present? ? "<<TABLE>#{str}</TABLE>>" : "why wouldn't area have area options?"))
=end        

          ensure_node.call("intelligent",nil,pos: "10,10")
          ensure_node.call("safety",nil,pos: "100,100")
          ensure_node.call("efficiency",nil,pos: "50,50")
          ensure_node.call("connectivity",nil,pos: "10,10")
          ensure_node.call("land use",nil,pos: "10,10")
          ensure_node.call("congestion",nil,pos: "10,10")
          ensure_node.call("complete streets",nil,pos: "10,10")
          ensure_node.call("public transit",nil,pos: "10,10")
          ensure_node.call("multimodal",nil,pos: "10,10")


          for k, hit_count in hits 
            ensure_node.call(k) 
          end

          {
            "intelligent" => ["safety","efficiency","maintenance"],
            "safety" => ["efficiency"],
            "efficiency" => ["mobility"],
            "congestion" => ["environment","efficiency"],
            "connectivity" => ["efficiency","efficiency"],
            "land use" => ["connectivity","walking","complete streets", "public transit","efficiency"],
            "complete streets" => ["walking","public transit","multimodal"],
            "public transit" => ["connectivity","multimodal"],
            "multimodal" => ["congestion"]
          }.each do |k,vs|
            ensure_node.call(k)
            for v in vs
              ensure_node.call(v)
              g.add_edges(nodes[k],nodes[v])
            end
          end
        #}.output(:png => "output.png")
        }.output(dot: output_filename)
        io.puts "#{output_filename} generated"
      end
    end
  end

  class PrintAll < Proc
    def self.new(*)
      Hirb.enable :pager=>false, :formatter=>false 

      super() do |io, hits, opts|  
        rows = hits.sort_by(&:last)

        first_count = rows.first.last
        rows.each do |row|
          scale = row.last / (1.0*first_count)
          row << scale.round
        end
        io.puts Hirb::Helpers::AutoTable.render(rows,opts.merge(headers: ['category',"blocks (#{$cli_options['block-size']} min chars) which meet criteria", 'scale (relative)']))

        option_and_value = $cli_options.dup
        option_and_value.delete('display')
        io.puts Hirb::Helpers::AutoTable.render(option_and_value.sort,headers: ["option","value"])
      end
    end
  end

  def initialize(path_to_prose_with_pdf_links, path_to_keywords)
    @pdf_paths = extract_and_download_pdfs(path_to_prose_with_pdf_links)
    if $cli_options["verbose"]
      STDOUT.puts("no more PDFs to download.")
    end

    hsh = YAML.load_file(path_to_keywords)
    @keywords = hsh["keywords"]

    @document_rules = hsh["documents"]

    #validate keywords
    if @keywords.to_json[/A-Z/]
      raise "keywords must all be lowercase. Keyword search matches BOTH capital and lowercase"
    end
    @keywords.each do |k,vs| 
      if !vs.include?(k) 
        raise "keyword variations for #{k} should include #{k} -- we don't automatically include it."
      end
    end

    if $cli_options["verbose"]
      STDOUT.puts("keywords extracted: #{@keywords.inspect}")
    end
  end
  def validate_document_rules
    @document_rules.each do |basename, drule|
      if !get_path_to_txt(basename).exist?
        raise "the document rules in keywords.yaml seem to be incorrect; no known file: #{basename}"
      end
    end
  end

  def process_all!
    validate_document_rules

    @hits = Hash.new{|h,k| h[k] = 0}
    @counts_for_each_block = {} #only used for verbose
    for path in @pdf_paths
      process_one!(path) do |block_number,counts|
        if $cli_options["verbose"]
          @counts_for_each_block[path.to_s+":#{block_number}"] = counts
        end
      end
    end
    @hits.freeze
    if $cli_options["verbose"]
      for (path_and_block, counts) in @counts_for_each_block.sort
        STDOUT.puts "#{path_and_block}: #{counts.to_json}"
      end
    end
    nil
  end


  def hits
    validate_populated
    @hits
  end


  def process_one!(path)
    block_number = 0
    io = path.open("r")
    until io.eof?
      string = ""
      block_number += 1

      begin 
        string += io.gets until (string.length > $cli_options["block-size"] || io.eof?)
      rescue
      end

      transaction_lite do |counts,error_master|
        for keyword, variations in @keywords
          valid_variations = variations.compact.reject{|v| @document_rules[path.basename.to_s] && Array(@document_rules[path.basename.to_s]['skip']).include?(v) }

          error_master.details = [path, keyword]
          #error_master.verbose = lambda{ }
          if $cli_options["verbose"]
            STDOUT.puts("#{path},#{keyword}, block_number #{block_number}")
          end
          found = string.scan(/#{valid_variations.join("|")}/i).compact  #case insensitive
          counts[keyword]
          if $cli_options['min-match-count'] 
            if found.length >= $cli_options['min-match-count']
              counts[keyword] += found.length
            end
          elsif found.any?
            counts[keyword] += found.length
          else
            #binding.pry
          end
        end

        if block_given?
          yield(counts)
        end
      end
    end
    nil
  end

  def transaction_lite
    tmp_counts = Hash.new{|h,k| h[k] = 0}
    error_master = OpenStruct.new #TODO: gather information from the context as a hash
    yield(tmp_counts,error_master)
    for k,count in tmp_counts
      @hits[k]
      if count > 0
        @hits[k] += 1
      end
    end
    nil
  rescue Exception => e
    if $cli_options["debug"]
      binding.pry
    end
    STDERR.puts("Error: #{error_master.inspect}, #{e.message}")
  end

private
  def validate_populated
    if @hits.nil?
      raise "please call process_all! before attempting to use the hit results."
    end
  end

  PDF_DIR = Pathname.new 'tmp/pdfs'
  FileUtils.mkdir_p(PDF_DIR)
  TXT_DIR = Pathname.new 'tmp/txt'
  FileUtils.mkdir_p(TXT_DIR)
  CLEANED_DIR = Pathname.new('cleaned/txt')
  raise "cleaned should be in git" unless CLEANED_DIR.exist?

  def extract_and_download_pdfs(path_to_prose_with_pdf_links)
    prose = File.read(path_to_prose_with_pdf_links)
    links = prose.scan(/http[^\s\n]*/).inject({}){|acc,l| 
        acc[File.basename(l)] = l; acc 
    }
    for basename, link in links
      next if cleaned_exists?(basename)
      if ENV['REFRESH_PDFS']
      else
        if PDF_DIR.join(basename).exist? && PDF_DIR.join(basename).size == 0
          STDERR.puts "Warning: #{PDF_DIR.join(basename).basename} is empty, but exists. Attempting to download again. If requires sign-in, please manually download. #{link}"
        elsif PDF_DIR.join(basename).exist?
          next
        end
      end

      #TODO: only overwrite if download is successful. Does curl automatically do this?
      open(PDF_DIR+basename, 'wb') do |file|
        file << open(link).read
      end
    end

    for basename, link in links
      next if cleaned_exists?(basename)
      if ENV['REFRESH_TXTS']
      else
        if TXT_DIR.join(basename).exist? && TXT_DIR.join(basename).size == 0
            STDERR.puts "Warning: #{TXT_DIR.join(basename).basename} is empty, but exists. Attempting to process to TXT again. If consistently failing, please create text manually. #{link}"
        elsif TXT_DIR.join(basename).exist?
            next
        end
      end
      io = open(PDF_DIR.join(basename).to_s)
      begin
        reader = PDF::Reader.new(io)
        string = "" 
        reader.pages.each do |page|
          begin
            string += page.text 
          rescue Exception
            STDERR.puts("failed to process page. continuing: #{page.inspect} from #{basename}")
          end
        end 
      rescue
        STDERR.puts("failed to process entire PDF. continuing: #{basename}")
      end
      open(TXT_DIR+basename, 'w+') do |file|
        file << string
      end
    end

    links.map{|basename,url| get_path_to_txt basename }
  end


  def cleaned_exists?(basename); CLEANED_DIR.join(basename).exist? end

  def get_path_to_txt(basename)
    if cleaned_exists?(basename)
      CLEANED_DIR.join basename
    else
      TXT_DIR.join basename
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  obj = WordHistograms.new(ARGV[0],ARGV[1])
  obj.process_all!

  opts = $cli_options.dup
  io = StringIO.new

  #constantize, not available without activesupport
  eval("WordHistograms::#{opts["display"]}").new.(io,obj.hits, opts)
  io.rewind
  STDOUT.puts(io.read)
end
