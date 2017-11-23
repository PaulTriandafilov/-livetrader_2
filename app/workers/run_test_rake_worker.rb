require 'rake'

class RunTestRakeWorker
  include Sidekiq::Worker
  Rake::Task.clear
  Bot::Application.load_tasks

  def perform(*args)
    puts "Starting task..."
    Rake::Task['bot:run'].reenable
    Rake::Task['bot:run'].invoke
  end
end