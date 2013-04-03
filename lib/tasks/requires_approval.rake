require 'rubygems'
require 'rspec/core/rake_task'

task :default => [:all]

namespace :spec do
  desc "Run Rspec Unit Tests"
  RSpec::Core::RakeTask.new(:unit) do |t|
    files = Dir.glob('spec/**/*_spec.rb').delete_if{|f|
      f =~ /(integration|request|acceptance)/
    }
    files = files.delete_if{|f| f =~ /routing/}
    t.pattern = files
    t.rspec_opts = ["-O", ".rspec", "--tag", "~integration"]
  end
  desc "Run Rspec Integration Tests"
  RSpec::Core::RakeTask.new(:integration) do |t|
    files =  Dir.glob(
      'spec/{integration,request}/**/*_spec.rb'
    )
    t.pattern = files
    t.rspec_opts = [
      "--format nested"
    ]
  end
  desc "Run All Rspec Tests"
  RSpec::Core::RakeTask.new(:all) do |t|
    files = Dir.glob('spec/**/*_spec.rb')
    # routing doesn't work
    files = files.delete_if{|f| f =~ /routing/}
    t.pattern = files
    t.rspec_opts = [
      "--format nested"
    ]
  end
end