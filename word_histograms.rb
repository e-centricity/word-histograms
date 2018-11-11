require 'yaml'
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
      io = open(path.to_s)
      reader = PDF::Reader.new(io)
      reader.pages.each do |page|
        string = page.text
        for keyword in @keywords
          error_master.path = path
          error_master.keyword = keyword
          error_master.page = page
          if ENV['VERBOSE']
            STDOUT.puts("#{path},#{keyword}, #{page.inspect}")
          end
          found = string.scan(keyword)
          counts[keyword]
          counts[keyword] += found.length
        end
      end

      if block_given?
        yield(counts)
      end

    end
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

  PDF_DIR = 'tmp/pdfs'
  def extract_and_download_pdfs(path_to_prose_with_pdf_links)
    FileUtils.mkdir_p(PDF_DIR)
    tmpdir = Pathname.new(PDF_DIR)
    #regexp = /(^$)|(^(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(([0-9]{1,5})?\/.*)?$)/ix
    #regexp = /^((http[s]?|ftp):\/)?\/?([^:\/\s]+)((\/\w+)*\/)([\w\-\.]+[^#?\s]+)(.*)?(#[\w\-]+)?$/
    regexp = /http[^\s\n]*/
    prose = File.read(path_to_prose_with_pdf_links)
    links = prose.scan(regexp).inject({}){|acc,l| 
        acc[File.basename(l)] = l; acc 
    }
    for basename, link in links
      if ENV['REFRESH']
      else
        if tmpdir.join(basename).size == 0
          STDERR.puts "Warning: #{path.basename} is empty, but exists. Attempting to download again. If requires sign-in, please manually download. #{link}"
        elsif tmpdir.join(basename).exist?
          next
        end
      end
      open(tmpdir+basename, 'wb') do |file|
        file << open(link).read
      end
    end
    links.map{|basename,url| tmpdir+basename }
  end

  def extract_keywords(path_to_keywords)
    File.read(path_to_keywords).split(/[\W{2,20}|,]/).reject{|candidate| !candidate[/\w/] }
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
