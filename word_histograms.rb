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
    @keywords = extract_keywords(path_to_keywords)
    if ENV['VERBOSE']
      STDOUT.puts("keywords extracted: #{@keywords.inspect}")
    end
  end

  def process_all!
    @counts = Hash.new{|h,k| h[k] = 0}
    @counts_for_each_page = {} #only used for verbose
    for path in @pdf_paths
      process_one!(path) do |counts|
        if ENV['VERBOSE']
          @counts_for_each_page[path] = counts
        end
      end
    end
    @counts.freeze
    if ENV['VERBOSE']
      for path, counts in @counts_for_each_page
        STDOUT.puts "#{path}: #{counts.to_json}"
      end
    end
    nil
  end


  def histograms
    validate_populated
    @counts
  end


  def process_one!(path)
    transaction_lite do |counts,error_master|
      string = path.read
      for keyword in @keywords
        error_master.details = [path, keyword]
        #error_master.verbose = lambda{ }
        if ENV['VERBOSE']
          STDOUT.puts("#{path},#{keyword}")
        end
        found = string.scan(keyword)
        counts[keyword]
        counts[keyword] += found.length
      end

      if block_given?
        yield(counts)
      end

    end
    nil
  end

  def transaction_lite
    tmp_counts = Hash.new{|h,k| h[k] = 0}
    error_master = OpenStruct.new #TODO: gather information from the context as a hash
    yield(tmp_counts,error_master)
    for k,count in tmp_counts
      @counts[k]
      @counts[k] += count
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
    if @counts.nil?
      raise "please call process_all! before attempting to use this."
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
        if pdfdir.join(basename).exist? && pdfdir.join(basename).size == 0
          STDERR.puts "Warning: #{pdfdir.join(basename).basename} is empty, but exists. Attempting to download again. If requires sign-in, please manually download. #{link}"
        elsif pdfdir.join(basename).exist?
          next
        end
      end

      #TODO: only overwrite if download is successful. Does curl automatically do this?
      open(pdfdir+basename, 'wb') do |file|
        file << open(link).read
      end
    end

    for basename, link in links
      next if cleaned_exists?(basename)
      if ENV['REFRESH_TXTS']
      else
        if txtdir.join(basename).exist? && txtdir.join(basename).size == 0
            STDERR.puts "Warning: #{txtdir.join(basename).basename} is empty, but exists. Attempting to process to TXT again. If consistently failing, please create text manually. #{link}"
        elsif txtdir.join(basename).exist?
            next
        end
      end
      io = open(pdfdir.join(basename).to_s)
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
      open(txtdir+basename, 'w+') do |file|
        file << string
      end
    end

    links.map{|basename,url| get_text basename }
  end

  def extract_keywords(path_to_keywords)
    File.read(path_to_keywords).split(/[\W{2,20}|,]/).reject{|candidate| !candidate[/\w/] }
  end

  def cleaned_exists?(basename); CLEANED_DIR.join(basename).exist? end

  def get_text(basename)
    if cleaned_exists?(basename)
      CLEANED_DIR.join basename
    else
      TXT_DIR.join basename
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  if(ARGV[0].nil? || ARGV[1].nil?)
    raise "USAGE:      VERBOSE=true DEBUG=true bundle exec ruby word_histograms.rb list_of_pdf_links.txt keywords.txt"
  end
  obj = WordHistograms.new(ARGV[0],ARGV[1])
  obj.process_all!
  #TODO: make it a
  STDOUT.puts(obj.histograms.to_yaml)
end
