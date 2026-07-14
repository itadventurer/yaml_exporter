# frozen_string_literal: true

require_relative 'test_helper'

module ManyPositionalTestModels
  class BookPart < ActiveRecord::Base
    self.table_name = 'book_parts'
    belongs_to :book, class_name: 'ManyPositionalTestModels::Book'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_many :book_parts, class_name: 'ManyPositionalTestModels::BookPart',
                          foreign_key: :book_id, dependent: :destroy

    include YamlExporter

    yaml_structure do
      attributes :title
      many :book_parts do
        attributes :title, :content, :position
      end
    end
  end
end

class ManyPositionalTest < Minitest::Test
  Book = ManyPositionalTestModels::Book
  BookPart = ManyPositionalTestModels::BookPart

  def setup
    reset_test_database!
  end

  def test_import_creates_children
    book = Book.new
    book.yaml_import(yaml_fixture('many_positional', doc: 0))

    reloaded(book) do |book|
      parts = book.book_parts.order(:id).to_a
      assert_equal 3, parts.size
      assert_equal ['Chapter 1', 'Chapter 2', 'Chapter 3'], parts.map(&:title)
      assert_equal [1, 2, 3], parts.map(&:position)
    end
  end

  def test_import_destroys_extras_when_list_shrinks
    book = Book.new
    book.yaml_import(yaml_fixture('many_positional', doc: 0))
    reloaded(book) { |book| assert_equal 3, book.book_parts.count }

    book.yaml_import(yaml_fixture('many_positional', doc: 1))

    reloaded(book) do |book|
      parts = book.book_parts.order(:id).to_a
      assert_equal 2, parts.size
      assert_equal ['Chapter 1', 'Chapter 2'], parts.map(&:title)
    end
  end

  def test_import_updates_in_place_and_adds_missing
    book = Book.new
    book.yaml_import(yaml_fixture('many_positional', doc: 0))
    original_ids = reloaded(book) { |book| book.book_parts.order(:id).pluck(:id) }

    book.yaml_import(yaml_fixture('many_positional', doc: 2))

    reloaded(book) do |book|
      parts = book.book_parts.order(:id).to_a
      assert_equal 4, parts.size
      # The first three rows keep their ids — update-in-place, not destroy-and-recreate.
      assert_equal original_ids, parts.first(3).map(&:id)
      assert_equal 'Chapter 4', parts.last.title
    end
  end

  def test_reordering_overwrites_by_array_index_the_documented_footgun
    book = Book.new
    book.yaml_import(yaml_fixture('many_positional', doc: 0))

    original_ids = reloaded(book) { |book| book.book_parts.order(:id).pluck(:id) }
    original_first_id = original_ids.first
    original_second_id = original_ids[1]

    # doc 3 swaps first and second entries — since identity is positional,
    # the existing rows keep their ids but each is overwritten with another's data.
    book.yaml_import(yaml_fixture('many_positional', doc: 3))

    reloaded(book) do |book|
      parts = book.book_parts.order(:id).to_a
      assert_equal 3, parts.size
      # The row previously holding "Chapter 1" (id=original_first_id) now holds Chapter 2's data.
      first_row = parts.find { |p| p.id == original_first_id }
      second_row = parts.find { |p| p.id == original_second_id }

      assert_equal 'Chapter 2', first_row.title
      assert_equal 2, first_row.position

      assert_equal 'Chapter 1', second_row.title
      assert_equal 1, second_row.position
    end
  end

  def test_export_preserves_sql_insertion_order
    book = Book.new
    book.yaml_import(yaml_fixture('many_positional', doc: 0))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)

      assert_equal(
        ['Chapter 1', 'Chapter 2', 'Chapter 3'],
        parsed['book_parts'].map { |h| h['title'] }
      )
    end
  end

  def test_round_trip
    book = Book.new
    book.yaml_import(yaml_fixture('many_positional', doc: 0))

    exported = reloaded(book) { |book| book.yaml_export }

    other = Book.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.book_parts.order(:id).pluck(:title, :content, :position),
                     other.book_parts.order(:id).pluck(:title, :content, :position)
      end
    end
  end
end
