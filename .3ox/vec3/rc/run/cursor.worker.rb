#!/usr/bin/env ruby
#
# CURSOR.WORKER.RB :: Runner script for Cursor Brains Worker
# Starts the worker process that consumes jobs from Redis queue
#

require_relative '../../lib/brains.cursor.rb'

if __FILE__ == $0
  begin
    puts "▛▞// Starting Cursor Brains Worker"
    puts "▛▞// Sirius time: #{sirius_time()}" if defined?(sirius_time)
    puts "▛▞// Worker will consume jobs from Redis queue..."
    puts "▛▞// Press Ctrl+C to stop"
    puts ""
    
    worker = CursorBrainsWorker.new
    worker.run
    
  rescue => e
    puts "▛▞// Fatal error: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end

:: ∎
