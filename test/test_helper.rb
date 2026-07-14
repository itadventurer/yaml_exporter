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

module YamlFixturePaths
  FIXTURE_YAML_DIR = File.expand_path('fixtures/yaml', __dir__)
end

# Order matters: child tables first, then parents — otherwise FOREIGN KEY
# constraints trip during DELETE. Mainline bookstore edges:
#   book_reviewers  -> books, reviewers
#   authors_books   -> authors, books
#   book_parts      -> books
#   book_details    -> books
#   books           -> publishers
# Edge-case coverage (non-id PK + multi-assoc-to-same-class) adds:
#   chapters           -> books
#   books_genres       -> books, genres
#   genre_assignments  -> books, genres
#   book_editors       -> books, people
#   book_coauthors     -> books, people
#   editorships        -> books, people
#   coauthorships      -> books, people
#   annotations        -> people
BOOKSTORE_TABLES = %w[
  book_reviewers
  authors_books
  book_parts
  book_details
  chapters
  books_genres
  genre_assignments
  book_editors
  book_coauthors
  editorships
  coauthorships
  annotations
  books
  corporate_users
  reviewers
  authors
  publishers
  genres
  people
  users
].freeze

def reset_test_database!
  connection = ActiveRecord::Base.connection
  BOOKSTORE_TABLES.each do |table|
    connection.execute("DELETE FROM #{connection.quote_table_name(table)}")
  end
  return unless connection.adapter_name.match?(/sqlite/i)

  BOOKSTORE_TABLES.each do |table|
    connection.execute(
      "DELETE FROM sqlite_sequence WHERE name=#{connection.quote(table)}"
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

  # Fetches `record` fresh from the DB by id and yields it. Use for every
  # post-import assertion block that verifies DB state, so we never rely on
  # the in-memory instance the importer just mutated.
  def reloaded(record)
    raise ArgumentError, 'reloaded() needs a persisted record' unless record.persisted?

    yield record.class.find(record.id)
  end
end
