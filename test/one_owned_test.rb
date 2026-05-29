# frozen_string_literal: true

require_relative 'test_helper'

module OneOwnedTestModels
  class BookDetail < ActiveRecord::Base
    self.table_name = 'book_details'
    belongs_to :book, class_name: 'OneOwnedTestModels::Book'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_one :book_detail, class_name: 'OneOwnedTestModels::BookDetail',
                          foreign_key: :book_id, dependent: :destroy

    include YamlExporter

    yaml_structure do
      attributes :title
      one :book_detail do
        attributes :summary, :publication_year
      end
    end
  end
end

class OneOwnedTest < Minitest::Test
  Book = OneOwnedTestModels::Book
  BookDetail = OneOwnedTestModels::BookDetail

  def setup
    reset_test_database!
  end

  def test_import_creates_book_detail_when_missing
    book = Book.new
    book.yaml_import(yaml_fixture('one_owned', doc: 0))

    reloaded(book) do |book|
      assert book.book_detail.present?
      assert_equal 'A practical introduction to Ruby on Rails development.', book.book_detail.summary
      assert_equal 2022, book.book_detail.publication_year
    end
  end

  def test_import_updates_existing_detail_in_place
    book = Book.new
    book.yaml_import(yaml_fixture('one_owned', doc: 0))
    detail_id = reloaded(book) { |book| book.book_detail.id }

    book.yaml_import(yaml_fixture('one_owned', doc: 3))

    reloaded(book) do |book|
      assert_equal detail_id, book.book_detail.id # same row, not recreated
      assert_equal 'Revised edition.', book.book_detail.summary
      assert_equal 2023, book.book_detail.publication_year
    end
  end

  def test_missing_key_destroys_existing_detail
    book = Book.new
    book.yaml_import(yaml_fixture('one_owned', doc: 0))
    detail_id = reloaded(book) { |book| book.book_detail.id }

    book.yaml_import(yaml_fixture('one_owned', doc: 1))

    reloaded(book) do |book|
      assert_nil book.book_detail
      refute BookDetail.exists?(detail_id)
    end
  end

  def test_null_value_destroys_existing_detail
    book = Book.new
    book.yaml_import(yaml_fixture('one_owned', doc: 0))
    detail_id = reloaded(book) { |book| book.book_detail.id }

    book.yaml_import(yaml_fixture('one_owned', doc: 2))

    reloaded(book) do |book|
      assert_nil book.book_detail
      refute BookDetail.exists?(detail_id)
    end
  end

  def test_export_emits_nested_hash_when_detail_present
    book = Book.new
    book.yaml_import(yaml_fixture('one_owned', doc: 0))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      assert_kind_of Hash, parsed['book_detail']
      assert_equal 'A practical introduction to Ruby on Rails development.', parsed['book_detail']['summary']
      assert_equal 2022, parsed['book_detail']['publication_year']
    end
  end

  def test_export_omits_detail_when_absent_by_default
    book = Book.create!(title: 'Ruby on Rails Tutorial')

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      refute parsed.key?('book_detail')
    end
  end

  def test_export_emits_null_when_detail_absent_and_omit_nil_disabled
    book = Book.create!(title: 'Ruby on Rails Tutorial')

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export(omit_nil: false))
      assert parsed.key?('book_detail')
      assert_nil parsed['book_detail']
    end
  end

  # A present child whose attributes are all nil exports as `{}` — it must be
  # kept, because omitting the key would destroy the child on re-import.
  def test_export_keeps_present_detail_with_only_nil_attributes
    book = Book.create!(title: 'Empty Detail')
    book.create_book_detail!

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      assert parsed.key?('book_detail')
      assert_equal({}, parsed['book_detail'])
    end
  end

  def test_export_round_trips_without_destroying_empty_detail
    book = Book.create!(title: 'Empty Detail')
    detail_id = book.create_book_detail!.id

    exported = reloaded(book) { |b| b.yaml_export }
    book.yaml_import(exported)

    reloaded(book) do |book|
      assert book.book_detail.present?
      assert_equal detail_id, book.book_detail.id
    end
  end

  # book_details.summary is a `text` column, so it exports as a literal block
  # scalar even for a short value.
  def test_export_renders_text_column_as_block_scalar
    book = Book.create!(title: 'T')
    book.create_book_detail!(summary: 'Hi')

    reloaded(book) do |book|
      yaml = book.yaml_export
      assert_includes yaml, 'summary: |-'
      assert_equal 'Hi', YAML.safe_load(yaml)['book_detail']['summary']
    end
  end

  def test_export_preserves_newlines_in_text_column
    book = Book.create!(title: 'T')
    book.create_book_detail!(summary: "line one\nline two")

    reloaded(book) do |book|
      yaml = book.yaml_export
      assert_includes yaml, 'summary: |-'
      assert_equal "line one\nline two", YAML.safe_load(yaml)['book_detail']['summary']
    end
  end

  def test_round_trip
    book = Book.new
    book.yaml_import(yaml_fixture('one_owned', doc: 0))

    exported = reloaded(book) { |book| book.yaml_export }
    other = Book.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.book_detail.summary,          other.book_detail.summary
        assert_equal book.book_detail.publication_year, other.book_detail.publication_year
      end
    end
  end
end
