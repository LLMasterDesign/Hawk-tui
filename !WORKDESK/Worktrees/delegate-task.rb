#!/usr/bin/env ruby
# delegate-task.rb
# Tool for delegating tasks to other agents in the multi-agent workflow

require 'fileutils'
require 'time'

TASK_QUEUE_FILE = File.join(File.dirname(__FILE__), ".agent-task-queue.md")

def next_task_id
  return "TASK-001" unless File.exist?(TASK_QUEUE_FILE)
  
  content = File.read(TASK_QUEUE_FILE)
  tasks = content.scan(/### (TASK-\d+)/)
  return "TASK-001" if tasks.empty?
  
  last_num = tasks.map { |t| t[0].split('-').last.to_i }.max
  "TASK-%03d" % (last_num + 1)
end

def add_task(assigned_to, assigned_by, description, file_path, priority = "medium")
  task_id = next_task_id
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
  
  task_entry = <<~TASK
### #{task_id}
- **Assigned To**: #{assigned_to}
- **Assigned By**: #{assigned_by}
- **Status**: pending
- **Priority**: #{priority}
- **Description**: #{description}
- **File**: #{file_path}
- **Created**: #{timestamp}
- **Updated**: #{timestamp}

TASK

  content = File.read(TASK_QUEUE_FILE)
  
  # Insert after "## Active Tasks" line
  if content.include?("## Active Tasks")
    content.sub!(/(## Active Tasks\n)/, "\\1\n#{task_entry}")
  else
    content = "## Active Tasks\n\n#{task_entry}\n" + content
  end
  
  File.write(TASK_QUEUE_FILE, content)
  puts "▛▞ Task Delegated ⫎▸"
  puts "   Task ID: #{task_id}"
  puts "   Assigned To: #{assigned_to}"
  puts "   Description: #{description}"
  puts "   File: #{file_path}"
  puts ""
  puts "Next: #{assigned_to} should check .agent-task-queue.md"
end

def update_task_status(task_id, status, notes = nil)
  return unless File.exist?(TASK_QUEUE_FILE)
  
  content = File.read(TASK_QUEUE_FILE)
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
  
  # Update status
  content.gsub!(/(### #{task_id}.*?- \*\*Status\*\*: )\w+/, "\\1#{status}")
  content.gsub!(/(### #{task_id}.*?- \*\*Updated\*\*: )[\d\s:-]+/, "\\1#{timestamp}")
  
  if notes
    content.gsub!(/(### #{task_id}.*?- \*\*Updated\*\*: [^\n]+\n)/, "\\1- **Notes**: #{notes}\n")
  end
  
  File.write(TASK_QUEUE_FILE, content)
  puts "✓ Updated #{task_id} status to: #{status}"
end

def list_tasks(agent = nil)
  return unless File.exist?(TASK_QUEUE_FILE)
  
  content = File.read(TASK_QUEUE_FILE)
  
  puts "▛▞ Agent Task Queue ⫎▸"
  puts ""
  
  tasks = content.scan(/### (TASK-\d+)(.*?)(?=### TASK-|\z)/m)
  
  tasks.each do |task_id, task_content|
    assigned_to = task_content[/\*\*Assigned To\*\*: (\w+)/, 1]
    status = task_content[/\*\*Status\*\*: (\w+)/, 1]
    description = task_content[/\*\*Description\*\*: ([^\n]+)/, 1]
    
    next if agent && assigned_to != agent
    
    status_icon = case status
    when "completed" then "✅"
    when "in_progress" then "🔄"
    when "blocked" then "⚠️"
    else "⏳"
    end
    
    puts "#{status_icon} #{task_id} → #{assigned_to}"
    puts "   #{description}"
    puts ""
  end
end

# CLI
if __FILE__ == $0
  command = ARGV[0]
  
  case command
  when "add"
    if ARGV.length < 4
      puts "Usage: delegate-task.rb add <assigned-to> <assigned-by> <description> <file-path> [priority]"
      exit 1
    end
    add_task(ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5] || "medium")
  when "update"
    if ARGV.length < 3
      puts "Usage: delegate-task.rb update <task-id> <status> [notes]"
      exit 1
    end
    update_task_status(ARGV[1], ARGV[2], ARGV[3])
  when "list"
    list_tasks(ARGV[1])
  else
    puts "▛▞ Task Delegation Tool ⫎▸"
    puts ""
    puts "Commands:"
    puts "  add <to> <by> <desc> <file> [priority]  Delegate a task"
    puts "  update <task-id> <status> [notes]      Update task status"
    puts "  list [agent]                            List tasks (optionally for agent)"
    puts ""
    puts "Examples:"
    puts "  delegate-task.rb add Agent2 Agent1 'Review changes' test-collaboration.md high"
    puts "  delegate-task.rb update TASK-001 in_progress"
    puts "  delegate-task.rb list Agent2"
  end
end
