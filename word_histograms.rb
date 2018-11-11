require 'yaml'
require 'json'
require 'open-uri'
require 'ostruct'
require 'pathname'
require 'pdf-reader'
require 'pry'

class WordHistograms

  def initialize(path_to_prose_with_pdf_links, path_to_keywords)
    @pdf_paths = extract_and_download_pdfs(path_to_prose_with_pdf_links)
    if ENV['VERBOSE']
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

    if ENV['VERBOSE']
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
        if ENV['VERBOSE']
          @counts_for_each_block[path.to_s+":#{block_number}"] = counts
        end
      end
    end
    @hits.freeze
    if ENV['VERBOSE']
      for (path_and_block, counts) in @counts_for_each_block.sort
        STDOUT.puts "#{path_and_block}: #{counts.to_json}"
      end
    end
    nil
  end


  def histograms
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
        string += io.gets until (string.length > 1000 || io.eof?)
      rescue
      end

      transaction_lite do |counts,error_master|
        for keyword, variations in @keywords
        binding.pry if path.to_s.include?("RTC")
          valid_variations = variations.reject{|v| @document_rules[path.basename.to_s] && Array(@document_rules[path.basename.to_s]['skip']).include?(v) }

          error_master.details = [path, keyword]
          #error_master.verbose = lambda{ }
          if ENV['VERBOSE']
            STDOUT.puts("#{path},#{keyword}, block_number #{block_number}, #{counts.values.inspect}")
          end
          found = string.scan(/#{valid_variations.join("|")}/i)  #case insensitive
          if found.any?
            counts[keyword]
            counts[keyword] += found.length
            break
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
    if ENV['DEBUG']
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
  if(ARGV[0].nil? || ARGV[1].nil?)
    raise "USAGE:      VERBOSE=true DEBUG=true bundle exec ruby word_histograms.rb list_of_pdf_links.txt keywords.yaml"
  end
  obj = WordHistograms.new(ARGV[0],ARGV[1])
  obj.process_all!
  #TODO: make it a
  STDOUT.puts(obj.histograms.to_yaml)
end
