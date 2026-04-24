# frozen_string_literal: true

require_relative 'test_helper'

module FullIntegrationTestModels
  class BookPart < ActiveRecord::Base
    self.table_name = 'book_parts'
    belongs_to :book, class_name: 'FullIntegrationTestModels::Book'
  end

  class BookDetail < ActiveRecord::Base
    self.table_name = 'book_details'
    belongs_to :book, class_name: 'FullIntegrationTestModels::Book'
  end

  class Author < ActiveRecord::Base
    self.table_name = 'authors'
    has_and_belongs_to_many :books,
                            class_name: 'FullIntegrationTestModels::Book',
                            join_table: 'authors_books'
  end

  class Publisher < ActiveRecord::Base
    self.table_name = 'publishers'
  end

  class Reviewer < ActiveRecord::Base
    self.table_name = 'reviewers'
  end

  class BookReviewer < ActiveRecord::Base
    self.table_name = 'book_reviewers'
    belongs_to :book,     class_name: 'FullIntegrationTestModels::Book'
    belongs_to :reviewer, class_name: 'FullIntegrationTestModels::Reviewer'
  end

  # Mirror of the README's "Putting it all together" example.
  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_many :book_parts, class_name: 'FullIntegrationTestModels::BookPart',
                          foreign_key: :book_id, dependent: :destroy
    has_one :book_detail, class_name: 'FullIntegrationTestModels::BookDetail',
                          foreign_key: :book_id, dependent: :destroy
    has_and_belongs_to_many :authors,
                            class_name: 'FullIntegrationTestModels::Author',
                            join_table: 'authors_books'
    belongs_to :publisher, class_name: 'FullIntegrationTestModels::Publisher', optional: true
    has_many :book_reviewers, class_name: 'FullIntegrationTestModels::BookReviewer',
                              foreign_key: :book_id, dependent: :destroy
    has_many :reviewers, through: :book_reviewers,
                         class_name: 'FullIntegrationTestModels::Reviewer'

    include YamlExporter

    yaml_structure do
      attributes :title, :price
      many :book_parts, find_by: :slug, positioned_by: :position do
        attributes :title, :content
      end
      one :book_detail do
        attributes :summary, :publication_year
      end
      many :authors, find_by: :slug
      one :publisher, find_by: :slug
      many :reviewers, through: :book_reviewers, find_by: :slug do
        attributes :finished
      end
    end
  end
end

class FullIntegrationTest < Minitest::Test
  Book = FullIntegrationTestModels::Book
  BookPart = FullIntegrationTestModels::BookPart
  BookDetail = FullIntegrationTestModels::BookDetail
  Author = FullIntegrationTestModels::Author
  Publisher = FullIntegrationTestModels::Publisher
  Reviewer = FullIntegrationTestModels::Reviewer
  BookReviewer = FullIntegrationTestModels::BookReviewer

  README_YAML = File.read(File.join(YamlFixturePaths::FIXTURE_YAML_DIR, 'full_integration.yml'))

  def setup
    reset_test_database!
    Publisher.create!(name: 'Addison-Wesley', slug: 'addison-wesley')
    Author.create!(name: 'Michael Hartl',    slug: 'michael-hartl')
    Author.create!(name: 'Another Author',   slug: 'another-author')
    Reviewer.create!(name: 'Alice',           slug: 'alice')
    Reviewer.create!(name: 'Bob',             slug: 'bob')
  end

  def test_import_builds_expected_object_graph
    book = Book.new
    book.yaml_import(README_YAML)

    reloaded(book) do |book|
      assert_equal 'Ruby on Rails Tutorial', book.title
      assert_equal 100.0, book.price

      parts = book.book_parts.order(:position).to_a
      assert_equal %w[chapter-1 chapter-2], parts.map(&:slug)
      assert_equal ['Chapter 1', 'Chapter 2'], parts.map(&:title)
      assert_equal [1, 2], parts.map(&:position)
      assert_equal ['This is the first chapter of the book', 'This is the second chapter of the book'],
                   parts.map(&:content)

      assert_equal 'A practical introduction to Ruby on Rails development.', book.book_detail.summary
      assert_equal 2022, book.book_detail.publication_year

      assert_equal %w[another-author michael-hartl], book.authors.pluck(:slug).sort

      assert_equal 'addison-wesley', book.publisher.slug

      assert_equal %w[alice bob], book.reviewers.pluck(:slug).sort
    end
  end

  def test_export_matches_readme_yaml_byte_for_byte
    book = Book.new
    book.yaml_import(README_YAML)

    reloaded(book) do |book|
      assert_equal README_YAML, book.yaml_export
    end
  end

  def test_export_has_no_leading_document_marker
    book = Book.new
    book.yaml_import(README_YAML)
    reloaded(book) do |book|
      refute book.yaml_export.start_with?("---\n"),
             'exported YAML must not start with a "---" document marker'
    end
  end

  def test_round_trip_idempotency
    book = Book.new
    book.yaml_import(README_YAML)

    first_export = reloaded(book) { |book| book.yaml_export }
    book.yaml_import(first_export)
    second_export = reloaded(book) { |book| book.yaml_export }

    assert_equal first_export, second_export
  end
end
