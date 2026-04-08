# frozen_string_literal: true

# Self-contained example demonstrating all YamlExporter features using an
# in-memory SQLite database.  Run from the repository root:
#
#   ruby examples/quiz.rb
#
# Prerequisites (one-time):
#
#   gem install sqlite3
#   bundle install

require "active_record"
require "json"
require_relative "../lib/yaml_exporter"

# -- Database setup (in-memory SQLite, no external services needed) -----------

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = nil

ActiveRecord::Schema.define do
  suppress_messages do
    create_table :quizzes do |t|
      t.string  :title,     null: false
      t.string  :quiz_type, null: false
    end

    create_table :questions do |t|
      t.references :quiz,          null: false
      t.string     :text,          null: false
      t.string     :question_type, null: false
      t.string     :feedback
    end

    create_table :answers do |t|
      t.references :question,   null: false
      t.string     :text,       null: false
      t.boolean    :is_correct, null: false
      t.integer    :impact
    end
  end
end

# -- Model definitions -------------------------------------------------------

class Answer < ActiveRecord::Base
  belongs_to :question
end

class Question < ActiveRecord::Base
  belongs_to :quiz
  has_many :answers, dependent: :destroy
end

class Quiz < ActiveRecord::Base
  include YamlExporter

  has_many :questions, dependent: :destroy

  yaml_structure do
    yaml_attribute :title, :quiz_type
    yaml_has_many :questions do
      yaml_attribute :text, :question_type, :feedback
      yaml_has_many :answers do
        yaml_attribute :text, :is_correct, :impact
      end
    end
  end
end

# -- Seed data ----------------------------------------------------------------

quiz = Quiz.create!(title: "Ruby Basics", quiz_type: "multiple_choice")

q1 = quiz.questions.create!(
  text: "What is Ruby?",
  question_type: "single_choice",
  feedback: "Ruby is a dynamic, open-source programming language."
)
q1.answers.create!(text: "A programming language", is_correct: true,  impact: 10)
q1.answers.create!(text: "A gemstone",             is_correct: false, impact: 0)
q1.answers.create!(text: "A color",                is_correct: false, impact: 0)

q2 = quiz.questions.create!(
  text: "Which keyword defines a method in Ruby?",
  question_type: "single_choice",
  feedback: "Use 'def' to define methods."
)
q2.answers.create!(text: "def",  is_correct: true,  impact: 10)
q2.answers.create!(text: "func", is_correct: false, impact: 0)
q2.answers.create!(text: "fn",   is_correct: false, impact: 0)

# -- 1. Export to YAML --------------------------------------------------------

puts "=" * 60
puts "1) YAML Export"
puts "=" * 60
yaml_output = quiz.yaml_export
puts yaml_output

# -- 2. Generate JSON Schema -------------------------------------------------

puts "=" * 60
puts "2) JSON Schema"
puts "=" * 60
schema = Quiz.yaml_schema
puts JSON.pretty_generate(schema)

# -- 3. Import from YAML (round-trip) ----------------------------------------

puts "\n" + "=" * 60
puts "3) YAML Import (round-trip into a new Quiz)"
puts "=" * 60

imported_quiz = Quiz.create!(title: "placeholder", quiz_type: "placeholder")
imported_quiz.yaml_import(yaml_output)

puts "Title:          #{imported_quiz.title}"
puts "Type:           #{imported_quiz.quiz_type}"
puts "Questions:      #{imported_quiz.questions.count}"
imported_quiz.questions.each do |q|
  puts "  Q: #{q.text}"
  q.answers.each do |a|
    marker = a.is_correct ? "✓" : "✗"
    puts "    #{marker} #{a.text} (impact: #{a.impact || 'n/a'})"
  end
end

puts "\n" + "=" * 60
puts "Done — all features working!"
puts "=" * 60
