# frozen_string_literal: true

require_relative 'test_helper'

module LifecycleTestModels
  class Publisher < ActiveRecord::Base
    self.table_name = 'publishers'
  end

  class BookDetail < ActiveRecord::Base
    self.table_name = 'book_details'
    belongs_to :book, class_name: 'LifecycleTestModels::Book'
  end

  class BookPart < ActiveRecord::Base
    self.table_name = 'book_parts'
    belongs_to :book, class_name: 'LifecycleTestModels::Book'
    validates :title, presence: true
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_many :book_parts, class_name: 'LifecycleTestModels::BookPart',
                          foreign_key: :book_id, dependent: :destroy
    has_one :book_detail, class_name: 'LifecycleTestModels::BookDetail',
                          foreign_key: :book_id, dependent: :destroy
    belongs_to :publisher, class_name: 'LifecycleTestModels::Publisher', optional: true

    include YamlExporter

    yaml_structure do
      attributes :title, :author
      many :book_parts, find_by: :slug do
        attributes :title, :content
      end
      one :book_detail do
        attributes :summary, :publication_year
      end
      one :publisher, find_by: :slug
    end
  end
end

class LifecycleTest < Minitest::Test
  Book = LifecycleTestModels::Book
  BookPart = LifecycleTestModels::BookPart
  BookDetail = LifecycleTestModels::BookDetail
  Publisher = LifecycleTestModels::Publisher

  def setup
    reset_test_database!
    @addison = Publisher.create!(name: 'Addison-Wesley', slug: 'addison-wesley')
  end

  def test_validation_failure_raises_record_invalid
    book = Book.new
    book.yaml_import(yaml_fixture('lifecycle', doc: 0))

    assert_raises(ActiveRecord::RecordInvalid) do
      book.yaml_import(yaml_fixture('lifecycle', doc: 1))
    end
  end

  def test_transaction_rolls_back_on_validation_failure
    book = Book.new
    book.yaml_import(yaml_fixture('lifecycle', doc: 0))

    before_title, before_author, before_part_slugs, before_detail_summary =
      reloaded(book) do |book|
        [book.title, book.author, book.book_parts.pluck(:slug).sort, book.book_detail.summary]
      end

    assert_raises(ActiveRecord::RecordInvalid) do
      book.yaml_import(yaml_fixture('lifecycle', doc: 1))
    end

    reloaded(book) do |book|
      assert_equal before_title,              book.title
      assert_equal before_author,             book.author
      assert_equal before_part_slugs,         book.book_parts.pluck(:slug).sort
      assert_equal before_detail_summary,     book.book_detail.summary
    end
  end

  def test_duplicate_find_by_keys_in_yaml_list_raise
    book = Book.new
    assert_raises(YamlExporter::DuplicateKeyError) do
      book.yaml_import(yaml_fixture('lifecycle', doc: 2))
    end
  end

  def test_omitted_keys_clear_attributes_owned_and_references
    book = Book.new
    book.yaml_import(yaml_fixture('lifecycle', doc: 0))
    reloaded(book) do |book|
      assert book.book_detail.present?
      assert_equal @addison.id, book.publisher_id
      refute_nil book.author
    end

    book.yaml_import(yaml_fixture('lifecycle', doc: 3))

    reloaded(book) do |book|
      assert_nil book.author
      assert_nil book.publisher_id
      assert_nil book.book_detail
      assert_equal 0, book.book_parts.count
      # Referenced publisher remains — references are cleared, not destroyed.
      assert Publisher.exists?(@addison.id)
    end
  end

  def test_explicit_null_clears_attributes_owned_and_references
    book = Book.new
    book.yaml_import(yaml_fixture('lifecycle', doc: 0))

    book.yaml_import(yaml_fixture('lifecycle', doc: 4))

    reloaded(book) do |book|
      assert_nil book.author
      assert_nil book.publisher_id
      assert_nil book.book_detail
      assert_equal 0, book.book_parts.count
    end
  end

  def test_undeclared_yaml_keys_raise_on_import
    book = Book.new
    assert_raises(YamlExporter::UnknownAttributeError) do
      book.yaml_import(yaml_fixture('lifecycle', doc: 5))
    end
  end
end
