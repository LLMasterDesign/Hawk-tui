#!/usr/bin/env ruby
#
# TEST.CURSOR.WORKFLOW.V3.RB :: Workflow using manifest and !WORKDESK
# Agent reads manifest, processes files from !WORKDESK, writes receipts
#

require 'json'
require 'net/http'
require 'uri'
require_relative '../../lib/cursor.api.rb'
require_relative '../../dev/ops/lib/helpers.rb'
require_relative '../../bin/sirius.clock.rb'

include Helpers

def create_workflow_prompt_v3
  """Create prompt for Cursor agent - uses manifest and !WORKDESK"""
  
  <<~PROMPT
    You are a 3OX agent operating in the CMD.BRIDGE workspace (GIT.BASE repository).
    
    CRITICAL FIRST STEP: Switch to main-monitor branch immediately:
    ```
    git checkout main-monitor
    ```
    The .3ox toolchain exists ONLY on main-monitor branch, not on master.
    After switching, verify .3ox exists:
    ```
    ls -la .3ox/vec3/dev/ops/
    ```
    You should see: prepare.for.agent.rb and lexicon.station.rb
    
    TASK: Analyze files and generate status reports using Lexicon Station.
    
    WORKFLOW:
    
    1. Switch to main-monitor branch (CRITICAL - do this first!)
    2. Verify .3ox structure exists
    
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
    
    2. Read the manifest file:
       ```
       cat CMD.CENTER/0ut.3ox/manifest.json
       ```
       The manifest lists all files available for processing with their paths.
    
    3. For each file listed in the manifest, run Lexicon Station analysis:
       ```
       ruby .3ox/vec3/dev/ops/lexicon.station.rb !WORKDESK/<agent-id>/<filename>
       ```
       Use the 'relative_path' from the manifest (e.g., !WORKDESK/Agent.1234567890/test.file.md)
       
       Use .3ox/vec3/var/wrkdsk/<agent-id>/ for any temporary work files.
       Output/print results to your !WORKDESK/<agent-id>/ folder.
    
    4. After processing all files, read all receipts from:
       ```
       CMD.CENTER/0ut.3ox/Jobs/*.receipt.json
       ```
    
    5. Generate a summary report:
       - Total files analyzed
       - Files that are Lexicon compliant (ready_for_commit: true)
       - Files that need review (ready_for_commit: false)
       - List of all issues found
       - Suggestions for fixes
    
    IMPORTANT PATHS:
    - Manifest: CMD.CENTER/0ut.3ox/manifest.json (shows your workspace folder name)
    - Your workspace: !WORKDESK/<agent-id>/ (for output/printing)
    - Your work dir: .3ox/vec3/var/wrkdsk/<agent-id>/ (for temporary work)
    - Files to process: Check manifest for exact paths
    - Analysis script: .3ox/vec3/dev/ops/lexicon.station.rb
    - Receipt output: CMD.CENTER/0ut.3ox/Jobs/
    
    START by running prepare.for.agent.rb, then follow the workflow above.
  PROMPT
end

def launch_cursor_agent(prompt)
  """Launch Cursor Cloud Agent"""
  puts "▛▞// Launching Cursor Cloud Agent (v3 - Manifest Workflow)..."
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
    puts "▛▞//   1. Agent will run prepare.for.agent.rb"
    puts "▛▞//   2. Read manifest from CMD.CENTER/0ut.3ox/manifest.json"
    puts "▛▞//   3. Process files from !WORKDESK/<agent-id>/"
    puts "▛▞//   4. Write receipts to CMD.CENTER/0ut.3ox/Jobs/"
    puts "▛▞//   5. Generate summary report"
    
    result
  rescue => e
    puts "▛▞// ERROR: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    nil
  end
end

if __FILE__ == $0
  prompt = create_workflow_prompt_v3
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
