#!/usr/bin/env ruby
#
# TEST.CURSOR.WORKFLOW.V4.RB :: Updated workflow - ensures master branch has files
# Agent should checkout master branch which now has .3ox structure
#

require 'json'
require 'net/http'
require 'uri'
require_relative '../../lib/cursor.api.rb'
require_relative '../../dev/ops/lib/helpers.rb'
require_relative '../../bin/sirius.clock.rb'

include Helpers

def create_workflow_prompt_v4
  """Create prompt for Cursor agent - updated for master branch"""
  
  <<~PROMPT
    You are a 3OX agent operating in the CMD.BRIDGE workspace (GIT.BASE repository).
    
    IMPORTANT: This repository uses the `master` branch which contains the .3ox toolchain.
    
    TASK: Analyze files and generate status reports using Lexicon Station.
    
    WORKFLOW:
    
    1. FIRST: Verify .3ox structure exists:
       ```
       ls -la .3ox/vec3/dev/ops/
       ```
       You should see: prepare.for.agent.rb and lexicon.station.rb
    
    2. Run the preparation script to scan !1N.3OX and set up your workspace:
       ```
       ruby .3ox/vec3/dev/ops/prepare.for.agent.rb
       ```
       This will:
       - Scan !1N.3OX directory (gitignored, so you can't access it directly)
       - Create your workspace folder in !WORKDESK/<agent-id>/
       - Copy files to your workspace
       - Create work directory in .3ox/vec3/var/wrkdsk/<agent-id>/
       - Generate manifest at CMD.CENTER/0ut.3ox/manifest.json
    
    3. Read the manifest file:
       ```
       cat CMD.CENTER/0ut.3ox/manifest.json
       ```
       The manifest lists all files available for processing with their paths.
    
    4. For each file listed in the manifest, run Lexicon Station analysis:
       ```
       ruby .3ox/vec3/dev/ops/lexicon.station.rb !WORKDESK/<agent-id>/<filename>
       ```
       Use the 'relative_path' from the manifest.
       
       Use .3ox/vec3/var/wrkdsk/<agent-id>/ for any temporary work files.
       Output/print results to your !WORKDESK/<agent-id>/ folder.
    
    5. After processing all files, read all receipts from:
       ```
       CMD.CENTER/0ut.3ox/Jobs/*.receipt.json
       ```
    
    6. Generate a summary report in your workspace:
       - Total files analyzed
       - Files that are Lexicon compliant (ready_for_commit: true)
       - Files that need review (ready_for_commit: false)
       - List of all issues found
       - Suggestions for fixes
       
       Save this report to: !WORKDESK/<agent-id>/ANALYSIS.REPORT.md
    
    IMPORTANT PATHS:
    - .3ox/vec3/dev/ops/prepare.for.agent.rb (preparation script)
    - .3ox/vec3/dev/ops/lexicon.station.rb (analysis script)
    - Manifest: CMD.CENTER/0ut.3ox/manifest.json (shows your workspace folder name)
    - Your workspace: !WORKDESK/<agent-id>/ (for output/printing)
    - Your work dir: .3ox/vec3/var/wrkdsk/<agent-id>/ (for temporary work)
    - Receipt output: CMD.CENTER/0ut.3ox/Jobs/
    
    START by verifying .3ox exists, then run prepare.for.agent.rb, then follow the workflow above.
  PROMPT
end

def launch_cursor_agent(prompt)
  """Launch Cursor Cloud Agent"""
  puts "▛▞// Launching Cursor Cloud Agent (v4 - Master Branch)..."
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
    
    puts "▛▞// Workflow:"
    puts "▛▞//   1. Agent verifies .3ox structure exists"
    puts "▛▞//   2. Runs prepare.for.agent.rb"
    puts "▛▞//   3. Reads manifest from CMD.CENTER/0ut.3ox/manifest.json"
    puts "▛▞//   4. Processes files from !WORKDESK/<agent-id>/"
    puts "▛▞//   5. Writes receipts to CMD.CENTER/0ut.3ox/Jobs/"
    puts "▛▞//   6. Generates summary report"
    
    result
  rescue => e
    puts "▛▞// ERROR: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    nil
  end
end

if __FILE__ == $0
  prompt = create_workflow_prompt_v4
  result = launch_cursor_agent(prompt)
  
  if result
    puts ""
    puts "▛▞// To check status:"
    puts "▛▞//   ruby test.cursor.workflow.rb --status #{result['id']}"
    puts ""
    puts "▛▞// To read receipts:"
    puts "▛▞//   ruby test.cursor.workflow.rb --read-receipts"
  end
end
