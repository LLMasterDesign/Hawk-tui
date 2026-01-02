#!/usr/bin/env ruby
# wrkdsk_bridge.rb :: Mirror bridge between !WORKDESK and vec3/var/wrkdsk
# Maintains synchronization with deduplication and integrity checking

require 'json'
require 'digest'
require 'fileutils'
require 'find'

class WrkdskBridge
  def initialize
    @vec3_root = File.expand_path('../..', __FILE__)
    @workdesk_root = File.expand_path('../../../!WORKDESK', __FILE__)
    @runtime_wrkdsk = File.join(@vec3_root, 'var', 'wrkdsk')
    @ledger_file = File.join(@vec3_root, 'var', 'state', 'wrkdsk.index.json')

    ensure_directories
    load_ledger
  end

  def sync_to_runtime
    puts "🔄 Syncing !WORKDESK → vec3/var/wrkdsk..."

    synced_count = 0
    skipped_count = 0

    Find.find(@workdesk_root) do |source_path|
      next if File.directory?(source_path)

      # Get relative path from workdesk root
      relative_path = source_path.sub(/^#{Regexp.escape(@workdesk_root)}\/?/, '')

      # Skip if empty relative path
      next if relative_path.empty?

      # Target path in runtime wrkdsk
      target_path = File.join(@runtime_wrkdsk, relative_path)

      # Ensure target directory exists
      FileUtils.mkdir_p(File.dirname(target_path))

      # Check if file needs syncing
      source_hash = compute_hash(source_path)
      target_hash = @ledger[relative_path]

      if source_hash != target_hash
        # Copy file
        FileUtils.cp(source_path, target_path)
        @ledger[relative_path] = source_hash
        synced_count += 1
        puts "  ✓ #{relative_path}"
      else
        skipped_count += 1
      end
    end

    save_ledger
    puts "✅ Sync complete: #{synced_count} synced, #{skipped_count} skipped"
  end

  def sync_to_workdesk
    puts "🔄 Syncing vec3/var/wrkdsk → !WORKDESK..."

    synced_count = 0
    skipped_count = 0

    Find.find(@runtime_wrkdsk) do |source_path|
      next if File.directory?(source_path)

      # Get relative path from runtime wrkdsk
      relative_path = source_path.sub(/^#{Regexp.escape(@runtime_wrkdsk)}\/?/, '')

      # Skip if empty relative path
      next if relative_path.empty?

      # Target path in workdesk
      target_path = File.join(@workdesk_root, relative_path)

      # Ensure target directory exists
      FileUtils.mkdir_p(File.dirname(target_path))

      # Check if file needs syncing
      source_hash = compute_hash(source_path)
      target_hash = @ledger["workdesk_#{relative_path}"]

      if source_hash != target_hash
        # Copy file
        FileUtils.cp(source_path, target_path)
        @ledger["workdesk_#{relative_path}"] = source_hash
        synced_count += 1
        puts "  ✓ #{relative_path}"
      else
        skipped_count += 1
      end
    end

    save_ledger
    puts "✅ Reverse sync complete: #{synced_count} synced, #{skipped_count} skipped"
  end

  def status
    workdesk_files = count_files(@workdesk_root)
    runtime_files = count_files(@runtime_wrkdsk)

    puts "📊 Wrkdsk Bridge Status:"
    puts "  !WORKDESK: #{workdesk_files} files"
    puts "  vec3/var/wrkdsk: #{runtime_files} files"
    puts "  Ledger entries: #{@ledger.size}"
    puts "  Last sync: #{last_sync_time || 'never'}"
  end

  private

  def ensure_directories
    [@runtime_wrkdsk, File.dirname(@ledger_file)].each do |dir|
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    end
  end

  def load_ledger
    @ledger = {}
    if File.exist?(@ledger_file)
      @ledger = JSON.parse(File.read(@ledger_file))
    end
  rescue
    @ledger = {}
  end

  def save_ledger
    @ledger['last_sync'] = Time.now.utc.iso8601
    File.write(@ledger_file, JSON.pretty_generate(@ledger))
  end

  def compute_hash(file_path)
    Digest::SHA256.file(file_path).hexdigest
  rescue
    nil
  end

  def count_files(directory)
    Dir.glob(File.join(directory, '**', '*')).count { |f| File.file?(f) }
  rescue
    0
  end

  def last_sync_time
    @ledger['last_sync']
  end
end

# Command line interface
if __FILE__ == $0
  bridge = WrkdskBridge.new

  case ARGV[0]
  when 'sync'
    bridge.sync_to_runtime
  when 'reverse'
    bridge.sync_to_workdesk
  when 'status'
    bridge.status
  when 'bidirectional'
    bridge.sync_to_runtime
    bridge.sync_to_workdesk
  else
    puts "Usage: ruby wrkdsk_bridge.rb {sync|reverse|status|bidirectional}"
    puts "  sync: !WORKDESK → vec3/var/wrkdsk"
    puts "  reverse: vec3/var/wrkdsk → !WORKDESK"
    puts "  status: Show synchronization status"
    puts "  bidirectional: Sync both directions"
  end
end