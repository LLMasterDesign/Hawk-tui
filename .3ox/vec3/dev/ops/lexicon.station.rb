#!/usr/bin/env ruby
#
# LEXICON.STATION.RB :: File Analysis Station with Lexicon Validation
# Analyzes files from !1N.3OX, validates via Lexicon, writes receipts to CMD.CENTER/0ut.3ox/Jobs
#

require 'json'
require 'time'
require 'fileutils'
require 'digest'
require_relative '../ops/lib/helpers.rb'
require_relative '../ops/cache/redis.rb'
require_relative '../../bin/sirius.clock.rb'

module LexiconStation
  include Helpers
  extend self

  # ============================================================================
  # FILE ANALYSIS
  # ============================================================================

  def analyze_file(file_path)
    """Analyze a file and return status report"""
    return nil unless File.exist?(file_path)
    
    file_info = {
      path: file_path,
      name: File.basename(file_path),
      size: File.size(file_path),
      modified: File.mtime(file_path).iso8601,
      type: detect_file_type(file_path),
      content_preview: read_preview(file_path),
      issues: [],
      suggestions: []
    }
    
    # Analyze content
    content = File.read(file_path) rescue ""
    
    # Check for common issues
    check_lexicon_compliance(file_info, content)
    check_formatting(file_info, content)
    check_structure(file_info, content)
    
    file_info
  end

  def detect_file_type(file_path)
    """Detect file type from extension and content"""
    ext = File.extname(file_path).downcase
    
    case ext
    when '.md', '.markdown'
      'markdown'
    when '.rb'
      'ruby'
    when '.exs', '.ex'
      'elixir'
    when '.json'
      'json'
    when '.yaml', '.yml'
      'yaml'
    when '.toml'
      'toml'
    else
      'text'
    end
  end

  def read_preview(file_path, lines: 20)
    """Read preview of file"""
    File.readlines(file_path).first(lines).join rescue ""
  end

  def check_lexicon_compliance(file_info, content)
    """Check if file follows Lexicon standards"""
    # Check for proper headers/banners
    if file_info[:type] == 'markdown'
      unless content.match?(/^\/\/\/▙▖▙▖▞▞▙/)
        file_info[:issues] << "Missing Lexicon banner header"
        file_info[:suggestions] << "Add Lexicon banner: ///▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂"
      end
      
      unless content.match?(/▛\/\/▞▞/)
        file_info[:issues] << "Missing section header"
        file_info[:suggestions] << "Add section header: ▛//▞▞"
      end
    end
    
    # Check for Sirius time
    unless content.match?(/⧗-\d+\.\d+/)
      file_info[:issues] << "Missing Sirius time"
      file_info[:suggestions] << "Add Sirius time: #{sirius_time()}"
    end
  end

  def check_formatting(file_info, content)
    """Check formatting issues"""
    lines = content.split("\n")
    
    # Check for trailing whitespace
    trailing_ws = lines.each_with_index.select { |line, i| line.match?(/\s+$/) }
    if trailing_ws.any?
      file_info[:issues] << "Trailing whitespace on #{trailing_ws.length} lines"
      file_info[:suggestions] << "Remove trailing whitespace"
    end
    
    # Check line length (warn if > 120)
    long_lines = lines.each_with_index.select { |line, i| line.length > 120 }
    if long_lines.any?
      file_info[:issues] << "#{long_lines.length} lines exceed 120 characters"
      file_info[:suggestions] << "Consider breaking long lines"
    end
  end

  def check_structure(file_info, content)
    """Check structural issues"""
    if file_info[:type] == 'markdown'
      # Check for proper closing markers
      unless content.match?(/::\s*∎/)
        file_info[:issues] << "Missing closing marker"
        file_info[:suggestions] << "Add closing marker: :: ∎"
      end
    end
  end

  # ============================================================================
  # RECEIPT GENERATION
  # ============================================================================

  def create_status_receipt(file_info, base_root)
    """Create status receipt for analyzed file"""
    trace_id = Digest::SHA256.hexdigest("#{file_info[:path]}#{Time.now.to_f}")[0..15]
    
    receipt = {
      'timestamp' => Time.now.utc.iso8601,
      'sirius_time' => sirius_time(),
      'actor' => 'lexicon_station',
      'intent' => 'file_analysis',
      'trace_id' => trace_id,
      'file' => {
        'path' => file_info[:path],
        'name' => file_info[:name],
        'type' => file_info[:type],
        'size' => file_info[:size],
        'modified' => file_info[:modified]
      },
      'analysis' => {
        'status' => file_info[:issues].empty? ? 'compliant' : 'needs_review',
        'issues_count' => file_info[:issues].length,
        'issues' => file_info[:issues],
        'suggestions' => file_info[:suggestions]
      },
      'validation' => {
        'lexicon_compliant' => file_info[:issues].empty?,
        'ready_for_commit' => file_info[:issues].empty?
      }
    }
    
    receipt
  end

  def write_receipt(receipt, base_root)
    """Write receipt to CMD.CENTER/0ut.3ox/Jobs"""
    # Try CMD.CENTER first, fallback to .OPS
    ops_dir = File.join(base_root, 'CMD.CENTER', '0ut.3ox', 'Jobs')
    unless File.directory?(ops_dir)
      ops_dir = File.join(base_root, '.OPS', '0ut.3ox', 'Jobs')
      FileUtils.mkdir_p(ops_dir)
    end
    
    receipt_file = File.join(ops_dir, "#{receipt['trace_id']}.receipt.json")
    File.write(receipt_file, JSON.pretty_generate(receipt))
    
    log_operation('lexicon_station', 'COMPLETE', "Receipt written: #{receipt_file}")
    
    receipt_file
  end

  # ============================================================================
  # MAIN PROCESSING
  # ============================================================================

  def process_file(file_path, base_root = nil)
    """Process a file: analyze, validate, write receipt"""
    base_root ||= File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..'))
    
    log_operation('lexicon_station', 'INFO', "Processing file: #{file_path}")
    
    # Analyze file
    file_info = analyze_file(file_path)
    
    unless file_info
      log_operation('lexicon_station', 'ERROR', "File not found: #{file_path}")
      return nil
    end
    
    # Create receipt
    receipt = create_status_receipt(file_info, base_root)
    
    # Write receipt
    receipt_path = write_receipt(receipt, base_root)
    
    # Return status report
    {
      file: file_info,
      receipt: receipt,
      receipt_path: receipt_path,
      status: receipt['analysis']['status']
    }
  end

  def process_inbox(base_root = nil)
    """Process all files in !1N.3OX"""
    base_root ||= File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..'))
    
    # Find !1N.3OX directory
    inbox_patterns = [
      File.join(base_root, '!1N.3OX'),
      File.join(base_root, '!1n.3ox'),
      File.join(base_root, '1N.3OX'),
      File.join(base_root, '1n.3ox')
    ]
    
    inbox_dir = inbox_patterns.find { |dir| File.directory?(dir) }
    
    unless inbox_dir
      log_operation('lexicon_station', 'WARNING', '!1N.3OX directory not found')
      return []
    end
    
    # Find all files
    files = Dir.glob(File.join(inbox_dir, '**', '*')).select { |f| File.file?(f) }
    
    results = []
    files.each do |file_path|
      result = process_file(file_path, base_root)
      results << result if result
    end
    
    results
  end
end

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

if __FILE__ == $0
  require 'optparse'
  
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: lexicon.station.rb [file_path] [options]"
    
    opts.on("-a", "--all", "Process all files in !1N.3OX") do
      options[:all] = true
    end
    
    opts.on("-b", "--base PATH", "Base root path") do |b|
      options[:base] = b
    end
    
    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end.parse!
  
  base_root = options[:base] || File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..'))
  
  if options[:all]
    puts "▛▞// Processing all files in !1N.3OX..."
    results = LexiconStation.process_inbox(base_root)
    
    puts "▛▞// Processed #{results.length} files"
    results.each do |result|
      status = result[:status]
      file_name = result[:file][:name]
      issues = result[:receipt]['analysis']['issues_count']
      
      status_icon = status == 'compliant' ? '✓' : '⚠'
      puts "▛▞//   #{status_icon} #{file_name} - #{issues} issues"
    end
  elsif ARGV.length > 0
    file_path = ARGV[0]
    result = LexiconStation.process_file(file_path, base_root)
    
    if result
      puts "▛▞// File Analysis Complete"
      puts "▛▞// File: #{result[:file][:name]}"
      puts "▛▞// Status: #{result[:status]}"
      puts "▛▞// Issues: #{result[:receipt]['analysis']['issues_count']}"
      puts "▛▞// Receipt: #{result[:receipt_path]}"
      
      if result[:receipt]['analysis']['issues'].any?
        puts "▛▞// Issues:"
        result[:receipt]['analysis']['issues'].each do |issue|
          puts "▛▞//   - #{issue}"
        end
      end
      
      if result[:receipt]['analysis']['suggestions'].any?
        puts "▛▞// Suggestions:"
        result[:receipt]['analysis']['suggestions'].each do |suggestion|
          puts "▛▞//   - #{suggestion}"
        end
      end
    else
      puts "▛▞// ERROR: Failed to process file"
      exit 1
    end
  else
    puts "Usage: lexicon.station.rb <file_path> or --all"
    puts "Run with -h for help"
    exit 1
  end
end
