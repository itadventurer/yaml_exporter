#!/usr/bin/env ruby
# frozen_string_literal: true

# Runnable demo sharing the same schema and models as the test suite.
# From the repository root:
#
#   ruby script/demo_quiz.rb
#
# One-time: gem install sqlite3 && bundle install

require 'bundler/setup'
require 'active_record'
require 'json'
require 'pathname'

root = Pathname.new(__dir__).join('..').expand_path
$LOAD_PATH.unshift root.join('lib').to_s
require 'yaml_exporter'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Base.logger = nil

load root.join('test/support/schema.rb')
load root.join('test/support/models.rb')

quiz = Quiz.create!(title: 'Ruby Basics', quiz_type: 'multiple_choice')

q1 = quiz.questions.create!(
  text: 'What is Ruby?',
  question_type: 'single_choice',
  feedback: 'Ruby is a dynamic, open-source programming language.'
)
q1.answers.create!(text: 'A programming language', is_correct: true, impact: 10)
q1.answers.create!(text: 'A gemstone', is_correct: false, impact: 0)
q1.answers.create!(text: 'A color', is_correct: false, impact: 0)

q2 = quiz.questions.create!(
  text: 'Which keyword defines a method in Ruby?',
  question_type: 'single_choice',
  feedback: "Use 'def' to define methods."
)
q2.answers.create!(text: 'def', is_correct: true, impact: 10)
q2.answers.create!(text: 'func', is_correct: false, impact: 0)
q2.answers.create!(text: 'fn', is_correct: false, impact: 0)

puts '=' * 60
puts '1) YAML Export'
puts '=' * 60
yaml_output = quiz.yaml_export
puts yaml_output

puts '=' * 60
puts '2) JSON Schema'
puts '=' * 60
schema = Quiz.yaml_schema
puts JSON.pretty_generate(schema)

puts "\n" + '=' * 60
puts '3) YAML Import (round-trip into a new Quiz)'
puts '=' * 60

imported_quiz = Quiz.create!(title: 'placeholder', quiz_type: 'placeholder')
imported_quiz.yaml_import(yaml_output)

puts "Title:          #{imported_quiz.title}"
puts "Type:           #{imported_quiz.quiz_type}"
puts "Questions:      #{imported_quiz.questions.count}"
imported_quiz.questions.each do |q|
  puts "  Q: #{q.text}"
  q.answers.each do |a|
    marker = a.is_correct ? '✓' : '✗'
    puts "    #{marker} #{a.text} (impact: #{a.impact || 'n/a'})"
  end
end

puts "\n" + '=' * 60
puts 'Done — all features working!'
puts '=' * 60
