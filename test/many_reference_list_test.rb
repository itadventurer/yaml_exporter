# frozen_string_literal: true

require_relative 'test_helper'

module ManyReferenceListTestModels
  class Author < ActiveRecord::Base
    self.table_name = 'authors'
    has_and_belongs_to_many :books,
                            class_name: 'ManyReferenceListTestModels::Book',
                            join_table: 'authors_books'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_and_belongs_to_many :authors,
                            class_name: 'ManyReferenceListTestModels::Author',
                            join_table: 'authors_books'

    include YamlExporter

    yaml_structure do
      attributes :title, :price
      many :authors, find_by: :slug
    end
  end
end

class ManyReferenceListTest < Minitest::Test
  Book = ManyReferenceListTestModels::Book
  Author = ManyReferenceListTestModels::Author

  def setup
    reset_test_database!
    @michael = Author.create!(name: 'Michael Hartl',            slug: 'michael-hartl')
    @dhh     = Author.create!(name: 'David Heinemeier Hansson', slug: 'david-heinemeier-hansson')
  end

  def test_import_resolves_each_slug_to_existing_author
    book = Book.new
    book.yaml_import(yaml_fixture('many_reference_list', doc: 0))

    reloaded(book) do |book|
      assert_equal [@dhh.id, @michael.id].sort, book.authors.pluck(:id).sort
    end
  end

  def test_import_does_not_auto_create_referenced_records
    assert_equal 2, Author.count
    book = Book.new
    book.yaml_import(yaml_fixture('many_reference_list', doc: 0))
    assert_equal 2, Author.count
  end

  def test_unresolvable_slug_raises_record_not_found
    book = Book.new
    assert_raises(ActiveRecord::RecordNotFound) do
      book.yaml_import(yaml_fixture('many_reference_list', doc: 3))
    end
  end

  def test_order_does_not_matter
    book_a = Book.new
    book_a.yaml_import(yaml_fixture('many_reference_list', doc: 0))

    book_b = Book.new
    book_b.yaml_import(yaml_fixture('many_reference_list', doc: 1))

    reloaded(book_a) do |book_a|
      reloaded(book_b) do |book_b|
        assert_equal book_a.authors.pluck(:id).sort, book_b.authors.pluck(:id).sort
      end
    end
  end

  def test_removal_only_drops_join_rows_not_the_author_itself
    book = Book.new
    book.yaml_import(yaml_fixture('many_reference_list', doc: 0))
    reloaded(book) { |book| assert_equal 2, book.authors.count }

    book.yaml_import(yaml_fixture('many_reference_list', doc: 2))

    reloaded(book) do |book|
      assert_equal [@michael.id], book.authors.pluck(:id)
      # Both Author rows still exist; only the join was dropped.
      assert Author.exists?(@dhh.id)
      assert Author.exists?(@michael.id)
    end
  end

  def test_export_emits_bare_strings_sorted_alphabetically
    book = Book.new
    book.yaml_import(yaml_fixture('many_reference_list', doc: 0))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      assert_equal ['david-heinemeier-hansson', 'michael-hartl'], parsed['authors']
    end
  end

  def test_round_trip
    book = Book.new
    book.yaml_import(yaml_fixture('many_reference_list', doc: 0))

    exported = reloaded(book) { |book| book.yaml_export }

    other = Book.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.authors.pluck(:id).sort, other.authors.pluck(:id).sort
      end
    end
  end
end
