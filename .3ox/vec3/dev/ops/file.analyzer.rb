#!/usr/bin/env ruby
#
# FILE.ANALYZER.RB :: Intelligent File Analysis for CMD.BRIDGE
# Analyzes dropped files and determines required actions
#

require 'json'
require 'fileutils'
require 'digest'
require_relative '../dev/ops/lib/helpers.rb'
require_relative '../dev/ops/cache/redis.rb'

module FileAnalyzer
  include Helpers
  extend self

  # ============================================================================
  # FILE ANALYSIS
  # ============================================================================

  def analyze_file(filepath, context = {})
    """Analyze file and determine what needs to be done with it"""
    
    file_info = gather_file_info(filepath)
    content_sample = extract_content_sample(filepath, file_info[:type])
    
    # Build analysis prompt
    prompt = build_analysis_prompt(filepath, file_info, content_sample, context)
    
    # Call LLM for analysis
    analysis = call_llm_analysis(prompt)
    
    # Parse analysis result
    parse_analysis_result(analysis, file_info)
  end

  def gather_file_info(filepath)
    {
      path: filepath,
      basename: File.basename(filepath),
      dirname: File.dirname(filepath),
      extension: File.extname(filepath),
      size: File.size(filepath),
      mtime: File.mtime(filepath),
      type: classify_file_type(filepath)
    }
  end

  def classify_file_type(filepath)
    ext = File.extname(filepath).downcase.sub(/^\./, '')
    
    case ext
    when 'md' then 'markdown'
    when 'txt' then 'text'
    when 'pdf' then 'pdf'
    when 'json', 'yaml', 'yml', 'toml' then 'data'
    when 'png', 'jpg', 'jpeg', 'gif', 'webp' then 'image'
    when 'rb', 'py', 'js', 'ex', 'exs' then 'code'
    when 'csv', 'xlsx' then 'spreadsheet'
    else 'unknown'
    end
  end

  def extract_content_sample(filepath, file_type)
    return nil unless ['markdown', 'text', 'code', 'data'].include?(file_type)
    return nil unless File.size(filepath) > 0
    
    begin
      # Read first 2KB for analysis
      content = File.read(filepath, 2048)
      content.force_encoding('UTF-8')
      content.valid_encoding? ? content : nil
    rescue
      nil
    end
  end

  def build_analysis_prompt(filepath, file_info, content_sample, context)
    """Build prompt for LLM file analysis"""
    
    prompt = <<~PROMPT
      Analyze this file and determine what actions need to be taken.

      FILE INFO:
      - Name: #{file_info[:basename]}
      - Type: #{file_info[:type]}
      - Size: #{file_info[:size]} bytes
      - Modified: #{file_info[:mtime]}

    PROMPT

    if content_sample
      prompt += <<~CONTENT
        CONTENT SAMPLE:
        ```
        #{content_sample}
        ```

      CONTENT
    end

    if context[:note]
      prompt += "USER NOTE: #{context[:note]}\n\n"
    end

    if context[:obsidian_refs]
      prompt += "OBSIDIAN REFERENCES: #{context[:obsidian_refs].join(', ')}\n\n"
    end

    prompt += <<~INSTRUCTIONS
      Determine what needs to be done with this file. Choose ONE primary action:

      1. MOVE - Just needs to be moved to a different location
      2. CODEX - Needs to be linked to a codex/knowledge base
      3. PROJECT - Needs to be connected to a project folder with support files
      4. GROUP - Needs to be grouped with other related files
      5. EDIT - Needs editing/processing in WORKDESK
      6. ARCHIVE - Should be archived/stored
      7. REFERENCE - Should be linked as reference material

      Respond in this format:
      ACTION: [action_type]
      REASON: [brief explanation]
      LOCATION: [suggested destination path or folder name]
      LINKS: [comma-separated list of files/projects to link to, if any]
      PRIORITY: [low/medium/high]
    INSTRUCTIONS

    prompt
  end

  def call_llm_analysis(prompt)
    """Call LLM provider for file analysis"""
    
    ask_script = File.join(get_vec3_root, 'dev', 'providers', 'ask.sh')
    
    unless File.exist?(ask_script)
      return fallback_analysis(prompt)
    end

    require 'open3'
    
    cmd = [
      'bash', ask_script,
      '-p', ENV['LLM_PROVIDER'] || 'openai',
      '-t', '0.3',  # Lower temperature for structured output
      '-x', '500',   # Shorter response
      '--no-stream',
      prompt
    ]

    stdout, stderr, status = Open3.capture3(*cmd)
    
    if status.success?
      stdout.strip
    else
      fallback_analysis(prompt)
    end
  rescue => e
    fallback_analysis(prompt)
  end

  def fallback_analysis(prompt)
    """Fallback analysis when LLM unavailable"""
    {
      action: 'EDIT',
      reason: 'Default action - LLM analysis unavailable',
      location: '!WORKDESK',
      links: [],
      priority: 'medium'
    }
  end

  def parse_analysis_result(analysis_text, file_info)
    """Parse LLM response into structured analysis"""
    
    result = {
      action: nil,
      reason: nil,
      location: nil,
      links: [],
      priority: 'medium',
      raw_analysis: analysis_text
    }

    # Parse structured response
    if analysis_text.is_a?(String)
      analysis_text.each_line do |line|
        case line
        when /^ACTION:\s*(.+)/i
          result[:action] = $1.strip.upcase
        when /^REASON:\s*(.+)/i
          result[:reason] = $1.strip
        when /^LOCATION:\s*(.+)/i
          result[:location] = $1.strip
        when /^LINKS:\s*(.+)/i
          result[:links] = $1.split(',').map(&:strip)
        when /^PRIORITY:\s*(.+)/i
          result[:priority] = $1.strip.downcase
        end
      end
    elsif analysis_text.is_a?(Hash)
      result = analysis_text
    end

    # Validate action
    valid_actions = ['MOVE', 'CODEX', 'PROJECT', 'GROUP', 'EDIT', 'ARCHIVE', 'REFERENCE']
    result[:action] = 'EDIT' unless valid_actions.include?(result[:action])

    result
  end

  # ============================================================================
  # ACTION EXECUTION
  # ============================================================================

  def execute_analysis_actions(filepath, analysis)
    """Execute the determined actions on the file"""
    
    project_root = get_project_root
    actions_taken = []

    case analysis[:action]
    when 'EDIT'
      # Copy to WORKDESK for editing
      workdesk = find_or_create_workdesk
      dest_path = File.join(workdesk, File.basename(filepath))
      FileUtils.cp(filepath, dest_path)
      actions_taken << "Copied to WORKDESK: #{dest_path}"

    when 'MOVE'
      # Move to specified location
      if analysis[:location]
        dest_dir = File.join(project_root, analysis[:location])
        FileUtils.mkdir_p(dest_dir)
        dest_path = File.join(dest_dir, File.basename(filepath))
        FileUtils.mv(filepath, dest_path)
        actions_taken << "Moved to: #{dest_path}"
      end

    when 'CODEX'
      # Link to codex + copy to WORKDESK
      create_codex_link(filepath, analysis)
      workdesk = find_or_create_workdesk
      dest_path = File.join(workdesk, File.basename(filepath))
      FileUtils.cp(filepath, dest_path)
      actions_taken << "Linked to codex"
      actions_taken << "Copied to WORKDESK: #{dest_path}"

    when 'PROJECT'
      # Create/link to project structure
      project_folder = create_project_structure(filepath, analysis)
      actions_taken << "Created project structure: #{project_folder}"
      
    when 'GROUP'
      # Group with related files
      group_folder = create_file_group(filepath, analysis)
      actions_taken << "Grouped in: #{group_folder}"

    when 'ARCHIVE'
      # Move to archive
      archive_dir = File.join(project_root, '!ARCHIVE', Time.now.strftime('%Y/%m'))
      FileUtils.mkdir_p(archive_dir)
      dest_path = File.join(archive_dir, File.basename(filepath))
      FileUtils.mv(filepath, dest_path)
      actions_taken << "Archived to: #{dest_path}"

    when 'REFERENCE'
      # Copy to reference location
      ref_dir = File.join(project_root, '!REFERENCE')
      FileUtils.mkdir_p(ref_dir)
      dest_path = File.join(ref_dir, File.basename(filepath))
      FileUtils.cp(filepath, dest_path)
      actions_taken << "Added to references: #{dest_path}"
    end

    actions_taken
  end

  def create_codex_link(filepath, analysis)
    """Create link in codex system"""
    # Stub for codex linking - implement based on your codex structure
    codex_dir = File.join(get_project_root, '!CODEX')
    FileUtils.mkdir_p(codex_dir)
    
    link_file = File.join(codex_dir, "#{File.basename(filepath, '.*')}.link.md")
    File.write(link_file, <<~LINK)
      # #{File.basename(filepath)}
      
      **Source:** #{filepath}
      **Reason:** #{analysis[:reason]}
      **Links:** #{analysis[:links].join(', ')}
      **Created:** #{Time.now.iso8601}
    LINK
  end

  def create_project_structure(filepath, analysis)
    """Create project folder with support files"""
    project_name = analysis[:location] || File.basename(filepath, '.*')
    project_dir = File.join(get_project_root, '!WORKDESK', project_name)
    
    FileUtils.mkdir_p(project_dir)
    FileUtils.mkdir_p(File.join(project_dir, 'support'))
    FileUtils.mkdir_p(File.join(project_dir, 'output'))
    
    # Move file to project
    FileUtils.cp(filepath, File.join(project_dir, File.basename(filepath)))
    
    # Create project readme
    File.write(File.join(project_dir, 'README.md'), <<~README)
      # #{project_name}
      
      **Created:** #{Time.now.iso8601}
      **Source:** #{filepath}
      **Reason:** #{analysis[:reason]}
      
      ## Related Files
      #{analysis[:links].map { |link| "- #{link}" }.join("\n")}
    README
    
    project_dir
  end

  def create_file_group(filepath, analysis)
    """Group file with related files"""
    group_name = analysis[:location] || 'group_' + Time.now.strftime('%Y%m%d')
    group_dir = File.join(get_project_root, '!GROUPS', group_name)
    
    FileUtils.mkdir_p(group_dir)
    FileUtils.cp(filepath, File.join(group_dir, File.basename(filepath)))
    
    group_dir
  end

  # ============================================================================
  # REDIS INTEGRATION
  # ============================================================================

  def store_analysis(filepath, analysis, actions_taken)
    """Store analysis result in Redis for future reference"""
    return unless RedisCache.redis_available?

    file_hash = Digest::SHA256.hexdigest(filepath)[0..15]
    
    record = {
      'filepath' => filepath,
      'file_hash' => file_hash,
      'analysis' => analysis,
      'actions_taken' => actions_taken,
      'timestamp' => Time.now.utc.iso8601
    }

    RedisCache.redis_set("file_analysis:#{file_hash}", record, 86400 * 30) # 30 days
  end

  def get_file_analysis(filepath)
    """Retrieve previous analysis for a file"""
    return nil unless RedisCache.redis_available?

    file_hash = Digest::SHA256.hexdigest(filepath)[0..15]
    RedisCache.redis_get("file_analysis:#{file_hash}")
  end
end

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

if __FILE__ == $0
  require 'optparse'
  
  options = { context: {} }
  OptionParser.new do |opts|
    opts.banner = "Usage: file.analyzer.rb [options] <filepath>"
    
    opts.on("-n", "--note NOTE", "Add user note for context") do |note|
      options[:context][:note] = note
    end
    
    opts.on("-o", "--obsidian REFS", "Obsidian references (comma-separated)") do |refs|
      options[:context][:obsidian_refs] = refs.split(',').map(&:strip)
    end
    
    opts.on("-e", "--execute", "Execute actions (not just analyze)") do
      options[:execute] = true
    end
    
    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end.parse!

  unless ARGV[0]
    puts "ERROR: No file specified"
    exit 1
  end

  filepath = ARGV[0]
  unless File.exist?(filepath)
    puts "ERROR: File not found: #{filepath}"
    exit 1
  end

  puts "▛▞// Analyzing: #{File.basename(filepath)}"
  analysis = FileAnalyzer.analyze_file(filepath, options[:context])
  
  puts "▛▞// Analysis Result:"
  puts "▛▞//   Action: #{analysis[:action]}"
  puts "▛▞//   Reason: #{analysis[:reason]}"
  puts "▛▞//   Location: #{analysis[:location]}" if analysis[:location]
  puts "▛▞//   Links: #{analysis[:links].join(', ')}" unless analysis[:links].empty?
  puts "▛▞//   Priority: #{analysis[:priority]}"

  if options[:execute]
    puts "▛▞// Executing actions..."
    actions = FileAnalyzer.execute_analysis_actions(filepath, analysis)
    actions.each { |action| puts "▛▞//   #{action}" }
    
    FileAnalyzer.store_analysis(filepath, analysis, actions)
    puts "▛▞// Complete!"
  else
    puts "▛▞// (Use --execute to perform actions)"
  end
end
