# encoding: utf-8

Dir.glob('lib/tasks/*.rake').each {|r| import r}
require 'rake'

require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end


require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "requires_approval"
  gem.homepage = "http://github.com/LifebookerInc/requires_approval"
  gem.license = "MIT"
  gem.summary = %Q{Gem to handle versioning and things that require approval}
  gem.description = %Q{Gem to handle versioning and things that require approval}
  gem.email = "dan.langevin@lifebooker.com"
  gem.authors = ["Dan Langevin"]
  # dependencies defined in Gemfile
end
Jeweler::RubygemsDotOrgTasks.new

require 'yard'
YARD::Rake::YardocTask.new
