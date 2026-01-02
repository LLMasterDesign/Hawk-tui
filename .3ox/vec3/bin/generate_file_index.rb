#!/usr/bin/env ruby
# Generate file index for .3ox with xxh64 hashes

require 'json'
require 'find'
require 'time'
require 'digest'

def xxh64_stub(filepath)
  # Stub: use first 16 chars of SHA256 as proxy for xxh64
  # In production, use actual xxh64 gem
  Digest::SHA256.file(filepath).hexdigest[0..15]
end

root = File.expand_path('../..', __dir__)
index = {
  index_version: '1.0.0',
  generated_at: Time.now.utc.iso8601,
  '3ox_root' => '.',
  file_inventory: {},
  directory_structure: {},
  summary: { total_files: 0, total_directories: 0, total_size_bytes: 0 },
  metadata: {
    generator: 'vec3 file indexer',
    integrity_mode: 'xxh64_stub',
    platform: RUBY_PLATFORM
  }
}

Find.find(root) do |path|
  next if path == root
  rel = path.sub("#{root}/", '')
  next if rel.start_with?('var/queue', 'var/receipts', 'var/logs', 'var/cache', 'tmp')
  
  if File.directory?(path)
    index[:directory_structure][rel] = {
      type: 'directory',
      permissions: File.stat(path).mode.to_s(8)[-3..-1],
      modified_at: File.mtime(path).utc.iso8601
    }
    index[:summary][:total_directories] += 1
  elsif File.file?(path)
    size = File.size(path)
    index[:file_inventory][rel] = {
      size_bytes: size,
      permissions: File.stat(path).mode.to_s(8)[-3..-1],
      modified_at: File.mtime(path).utc.iso8601,
      xxh64: xxh64_stub(path),
      type: 'file'
    }
    index[:summary][:total_files] += 1
    index[:summary][:total_size_bytes] += size
  end
end

index[:summary][:average_file_size] = index[:summary][:total_files] > 0 ? 
  index[:summary][:total_size_bytes] / index[:summary][:total_files] : 0

output_path = File.join(root, 'vec3/var/file.index.json')
File.write(output_path, JSON.pretty_generate(index))
puts "File index generated: #{output_path}"
puts "Files: #{index[:summary][:total_files]}, Dirs: #{index[:summary][:total_directories]}"
