#!/usr/bin/env ruby
#
# TEST.CURSOR.WORKFLOW.RB :: Test 3OX workflow via Cursor Cloud Agent API
# Launches Cursor agent to analyze files from !1N.3OX and generate receipts
#

require 'json'
require 'net/http'
require 'uri'
require_relative '../../lib/cursor.api.rb'
require_relative '../../dev/ops/lib/helpers.rb'
require_relative '../../bin/sirius.clock.rb'

include Helpers

def create_workflow_prompt(file_path = nil)
  """Create prompt for Cursor agent to run 3OX workflow"""
  
  base_prompt = <<~PROMPT
    You are a 3OX agent operating in the CMD.BRIDGE workspace.
    
    TASK: Analyze files from !1N.3OX directory and generate status reports.
    
    WORKFLOW:
    1. Find files in !1N.3OX directory
    2. For each file, run: ruby .3ox/vec3/dev/ops/lexicon.station.rb <file_path>
    3. The script will:
       - Analyze the file for Lexicon compliance
       - Check formatting, structure, and standards
       - Generate a status report
       - Write receipt to CMD.CENTER/0ut.3ox/Jobs/
    4. Read the receipt file from CMD.CENTER/0ut.3ox/Jobs/
    5. Report back:
       - File name and type
       - Analysis status (compliant/needs_review)
       - Number of issues found
       - List of issues and suggestions
       - Receipt location
    
    DIRECTORY STRUCTURE:
    - !1N.3OX/ - Input files (inbox)
    - .3ox/vec3/dev/ops/lexicon.station.rb - Analysis script
    - CMD.CENTER/0ut.3ox/Jobs/ - Receipt output location
    
    START by listing files in !1N.3OX, then analyze each one.
  PROMPT
  
  if file_path
    base_prompt += "\n\nSPECIFIC FILE: Analyze #{file_path} specifically.\n"
  end
  
  base_prompt
end

def launch_cursor_agent(prompt)
  """Launch Cursor Cloud Agent with workflow prompt"""
  puts "▛▞// Launching Cursor Cloud Agent..."
  puts "▛▞// Sirius time: #{sirius_time()}"
  puts ""
  
  begin
    result = CursorAPI.launch_agent(prompt, {
      model: 'gpt-5.2'
    })
    
    puts "▛▞// Agent launched successfully!"
    puts "▛▞// Agent ID: #{result['id']}"
    puts "▛▞// Status: #{result['status']}"
    puts "▛▞// View at: #{result.dig('target', 'url')}"
    puts ""
    
    if result['status'] == 'CREATING'
      puts "▛▞// Agent is being created. It will process files and write receipts."
      puts "▛▞// Check CMD.CENTER/0ut.3ox/Jobs/ for receipts when complete."
      puts "▛▞// Or check agent status at: #{result.dig('target', 'url')}"
    end
    
    result
  rescue => e
    puts "▛▞// ERROR: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    nil
  end
end

def check_agent_status(agent_id)
  """Check status of launched agent"""
  api_key = CursorAPI.load_api_key
  return nil unless api_key
  
  uri = URI("https://api.cursor.com/v0/agents/#{agent_id}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{api_key}"
  request['Content-Type'] = 'application/json'
  
  response = http.request(request)
  
  if response.code == '200'
    JSON.parse(response.body)
  else
    nil
  end
end

def read_receipts(receipts_dir)
  """Read receipts from CMD.CENTER/0ut.3ox/Jobs"""
  receipts = []
  
  return receipts unless File.directory?(receipts_dir)
  
  Dir.glob(File.join(receipts_dir, '*.receipt.json')).each do |receipt_file|
    begin
      receipt = JSON.parse(File.read(receipt_file))
      receipts << {
        file: receipt_file,
        data: receipt
      }
    rescue => e
      puts "▛▞// WARNING: Failed to read receipt #{receipt_file}: #{e.message}"
    end
  end
  
  receipts
end

# ============================================================================
# MAIN EXECUTION
# ============================================================================

if __FILE__ == $0
  require 'optparse'
  
  options = {
    file: nil,
    check_status: nil,
    read_receipts: false
  }
  
  OptionParser.new do |opts|
    opts.banner = "Usage: test.cursor.workflow.rb [options]"
    
    opts.on("-f", "--file PATH", "Specific file to analyze") do |f|
      options[:file] = f
    end
    
    opts.on("-s", "--status AGENT_ID", "Check agent status") do |s|
      options[:check_status] = s
    end
    
    opts.on("-r", "--read-receipts", "Read and display receipts") do
      options[:read_receipts] = true
    end
    
    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end.parse!
  
  base_root = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..'))
  receipts_dir = File.join(base_root, 'CMD.CENTER', '0ut.3ox', 'Jobs')
  
  if options[:check_status]
    puts "▛▞// Checking agent status: #{options[:check_status]}"
    status = check_agent_status(options[:check_status])
    
    if status
      puts JSON.pretty_generate(status)
    else
      puts "▛▞// ERROR: Failed to get agent status"
      exit 1
    end
    
  elsif options[:read_receipts]
    puts "▛▞// Reading receipts from: #{receipts_dir}"
    receipts = read_receipts(receipts_dir)
    
    if receipts.empty?
      puts "▛▞// No receipts found"
    else
      puts "▛▞// Found #{receipts.length} receipt(s):"
      puts ""
      
      receipts.each do |receipt_info|
        receipt = receipt_info[:data]
        puts "▛▞// Receipt: #{File.basename(receipt_info[:file])}"
        puts "▛▞//   File: #{receipt['file']['name']}"
        puts "▛▞//   Status: #{receipt['analysis']['status']}"
        puts "▛▞//   Issues: #{receipt['analysis']['issues_count']}"
        puts "▛▞//   Lexicon Compliant: #{receipt['validation']['lexicon_compliant']}"
        puts "▛▞//   Ready for Commit: #{receipt['validation']['ready_for_commit']}"
        puts ""
      end
    end
    
  else
    # Launch agent
    prompt = create_workflow_prompt(options[:file])
    result = launch_cursor_agent(prompt)
    
    if result
      puts ""
      puts "▛▞// To check status later, run:"
      puts "▛▞//   ruby test.cursor.workflow.rb --status #{result['id']}"
      puts ""
      puts "▛▞// To read receipts, run:"
      puts "▛▞//   ruby test.cursor.workflow.rb --read-receipts"
    end
  end
end
