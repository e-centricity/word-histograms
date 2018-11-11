require 'yaml'
require 'open-uri'
require 'pathname'
#require 'pdf-reader'
require 'origami' #more flexible than pdf-reader
require 'pry'

# Force data extraction, even for invalid FlateDecode streams.
Origami::OPTIONS[:ignore_zlib_errors] = true
Origami::OPTIONS[:ignore_png_errors] = true

class WordHistograms
  include Origami
  def initialize(path_to_prose_with_pdf_links, path_to_keywords)
    @pdf_paths = extract_and_download_pdfs(path_to_prose_with_pdf_links)
    @keywords = extract_keywords(path_to_keywords)
  end

  def process_all!
    @counts = Hash.new{|h,k| h[k] = 0}
    for path in @pdf_paths
      process_one!(path)
    end
    @counts.freeze
    nil
  end


  def histograms
    validate_populated
    @counts
  end


  def process_one!(path)
    transaction_lite(path) do |counts|
      #io = open(path.to_s)
      #reader = PDF::Reader.new(io)
      reader = PDF.read(path.to_s, lazy: true)
      reader.each_page do |page|
        #string = page.text
        string = page.to_s
        for keyword in @keywords
          @current_keyword = keyword
          @found = string.scan(keyword)
          counts[keyword]
          counts[keyword] += @found.length
        end
      end
    end
  end

  def transaction_lite(path)
    tmp_counts = Hash.new{|h,k| h[k] = 0}
    yield(tmp_counts)
    #transactions-lite
    for k,count in tmp_counts
      @counts[k]
      @counts[k] += count
    end
    nil
  rescue Exception => e
    STDERR.puts("Error: #{path}, #{@current_keyword}, #{@found}")
    binding.pry
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
    File.read(path_to_keywords).split(/[\W{2,20}|,]/)
  end
end

if __FILE__ == $PROGRAM_NAME
  obj = WordHistograms.new(ARGV[0],ARGV[1])
  obj.process_all!
  #TODO: make it a
  STDOUT.puts(obj.histograms.to_yaml)
end
