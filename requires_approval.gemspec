# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'requires_approval/version'

Gem::Specification.new do |s|
  s.name = "requires_approval"
  s.version = RequiresApproval::VERSION

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Dan Langevin"]
  s.date = "2012-10-12"
  s.summary = "Gem to handle versioning and things that require approval"
  s.description = "Gem to handle versioning and things that require approval"
  s.email = "dan.langevin@lifebooker.com"
  s.homepage = "http://github.com/LifebookerInc/requires_approval"
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.files         = `git ls-files`.split($/)
  s.executables   = s.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]
  s.rubygems_version = "1.8.11"

  s.add_runtime_dependency(%q<activerecord>, ["~> 3"])
  s.add_runtime_dependency(%q<activesupport>, ["~> 3"])
  s.add_development_dependency(%q<bundler>, [">= 0"])
  s.add_development_dependency(%q<guard-rspec>, [">= 0"])
  s.add_development_dependency(%q<guard-bundler>, [">= 0"])
  s.add_development_dependency(%q<guard-spork>, [">= 0"])
  s.add_development_dependency(%q<jeweler>, ["~> 1.8.3"])
  s.add_development_dependency(%q<mocha>, [">= 0"])
  s.add_development_dependency(%q<rdoc>, [">= 0"])
  s.add_development_dependency(%q<rspec>, [">= 0"])
  s.add_development_dependency(%q<ruby-debug19>, [">= 0"])
  s.add_development_dependency(%q<sqlite3>, [">= 0"])
  s.add_development_dependency(%q<yard>, [">= 0"])
end

