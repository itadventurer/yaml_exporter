# frozen_string_literal: true

# Defines the `build`/`install`/`release` tasks from the gemspec. The
# rubygems/release-gem CI action runs `rake release` to push the gem.
require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.warning = false
end

task default: :test
