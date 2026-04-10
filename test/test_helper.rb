# frozen_string_literal: true

require 'bundler/setup'
require 'active_record'
require 'yaml'
require 'yaml_exporter'
require 'minitest/autorun'
require 'minitest/pride'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

load File.expand_path('support/schema.rb', __dir__)
load File.expand_path('support/models.rb', __dir__)

module YamlFixturePaths
  FIXTURE_YAML_DIR = File.expand_path('fixtures/yaml', __dir__)
end

def reset_test_database!
  [ArticleNote, Article, Response, Answer, Question, Quiz, TrainingVm, Training, Vm].each(&:delete_all)
  return unless ActiveRecord::Base.connection.adapter_name.match?(/sqlite/i)

  %w[article_notes articles responses answers questions quizzes training_vms trainings vms].each do |table|
    ActiveRecord::Base.connection.execute(
      "DELETE FROM sqlite_sequence WHERE name=#{ActiveRecord::Base.connection.quote(table)}"
    )
  rescue ActiveRecord::StatementInvalid
    # table never had a row; sequence entry may be absent
  end
end

class Minitest::Test
  # Multi-document YAML fixtures: pass doc: index (0-based) to select one document as a single import string.
  def yaml_fixture(name, doc: 0)
    path = File.join(YamlFixturePaths::FIXTURE_YAML_DIR, "#{name}.yml")
    docs = YAML.load_stream(File.read(path))
    raise ArgumentError, "fixture #{name}.yml: no document at index #{doc}" if doc.negative? || doc >= docs.size

    YAML.dump(docs[doc])
  end
end
