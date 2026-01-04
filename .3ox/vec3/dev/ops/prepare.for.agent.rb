#!/usr/bin/env ruby
#
# PREPARE.FOR.AGENT.RB :: Scan !1N.3OX, generate manifest, copy to !WORKDESK
# Makes files accessible to Cursor Cloud Agent (since !1N.3OX is gitignored)
#

require 'json'
require 'fileutils'
require 'time'
require_relative 'query.1n3ox.rb'
require_relative 'lib/helpers.rb'
require_relative '../../bin/sirius.clock.rb'

include Helpers

def scan_and_prepare(base_root = nil)
  """Scan !1N.3OX, generate manifest, copy files to !WORKDESK"""
  base_root ||= File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..'))
  
  # Find !1N.3OX directory
  inbox_dir = Query1N3OX.find_1n3ox_dir
  
  unless File.directory?(inbox_dir)
    puts "▛▞// ERROR: !1N.3OX directory not found"
    return nil
  end
  
  # Scan directory
  scan_result = Query1N3OX.scan_directory(inbox_dir)
  
  if scan_result[:error]
    puts "▛▞// ERROR: #{scan_result[:error]}"
    return nil
  end
  
  files = scan_result[:files]
  
  if files.empty?
    puts "▛▞// No files found in !1N.3OX"
    return { manifest: [], workdesk_dir: nil }
  end
  
  # Each agent creates its own workspace in !WORKDESK
  # Use agent ID or timestamp-based folder name
  agent_id = ENV['CURSOR_AGENT_ID'] || "Agent.#{Time.now.to_i}"
  workdesk_dir = File.join(base_root, '!WORKDESK', agent_id)
  FileUtils.mkdir_p(workdesk_dir)
  
  # Also ensure vec3/var/wrkdsk exists for agent work
  wrkdsk_dir = File.join(base_root, '.3ox', 'vec3', 'var', 'wrkdsk', agent_id)
  FileUtils.mkdir_p(wrkdsk_dir)
  
  # Create manifest
  manifest = {
    'timestamp' => Time.now.utc.iso8601,
    'sirius_time' => sirius_time(),
    'source_dir' => inbox_dir,
    'workdesk_dir' => workdesk_dir,
    'files' => []
  }
  
  # Copy files to !WORKDESK and add to manifest
  files.each do |file_info|
    source_path = file_info['path']
    file_name = file_info['name']
    dest_path = File.join(workdesk_dir, file_name)
    
    # Copy file
    FileUtils.cp(source_path, dest_path)
    
    # Add to manifest
    manifest['files'] << {
      'name' => file_name,
      'source_path' => source_path,
      'workdesk_path' => dest_path,
      'relative_path' => "!WORKDESK/#{agent_id}/#{file_name}",
      'type' => file_info['type'],
      'size' => file_info['size'],
      'mtime' => file_info['mtime']
    }
  end
  
  # Write manifest to tracked location
  manifest_file = File.join(base_root, 'CMD.CENTER', '0ut.3ox', 'manifest.json')
  FileUtils.mkdir_p(File.dirname(manifest_file))
  File.write(manifest_file, JSON.pretty_generate(manifest))
  
  puts "▛▞// Scanned !1N.3OX: #{files.length} files"
  puts "▛▞// Agent workspace: !WORKDESK/#{agent_id}/"
  puts "▛▞// Work directory: .3ox/vec3/var/wrkdsk/#{agent_id}/"
  puts "▛▞// Manifest: CMD.CENTER/0ut.3ox/manifest.json"
  
  {
    manifest: manifest,
    manifest_file: manifest_file,
    workdesk_dir: workdesk_dir,
    files_count: files.length
  }
end

if __FILE__ == $0
  result = scan_and_prepare
  
  if result
    agent_folder = File.basename(result[:manifest]['workdesk_dir'])
    puts ""
    puts "▛▞// Files available for agent:"
    result[:manifest]['files'].each do |file|
      puts "▛▞//   - #{file['relative_path']} (#{file['type']})"
    end
    puts ""
    puts "▛▞// Agent workspace: !WORKDESK/#{agent_folder}/"
    puts "▛▞// Use this folder for output/printing"
    puts "▛▞// Use .3ox/vec3/var/wrkdsk/#{agent_folder}/ for work files"
    puts "▛▞// Manifest location: CMD.CENTER/0ut.3ox/manifest.json"
  end
end
