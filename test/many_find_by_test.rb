# frozen_string_literal: true

require_relative 'test_helper'

module ManyFindByTestModels
  class BookPart < ActiveRecord::Base
    self.table_name = 'book_parts'
    belongs_to :book, class_name: 'ManyFindByTestModels::Book'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_many :book_parts, class_name: 'ManyFindByTestModels::BookPart',
                          foreign_key: :book_id, dependent: :destroy

    include YamlExporter

    yaml_structure do
      attributes :title
      many :book_parts, find_by: :slug do
        attributes :title, :content, :position
      end
    end
  end
end

class ManyFindByTest < Minitest::Test
  Book = ManyFindByTestModels::Book
  BookPart = ManyFindByTestModels::BookPart

  def setup
    reset_test_database!
  end

  def test_matches_by_slug_regardless_of_yaml_order
    book = Book.new
    book.yaml_import(yaml_fixture('many_find_by', doc: 0))

    reloaded(book) do |book|
      by_slug = book.book_parts.each_with_object({}) { |p, h| h[p.slug] = p }
      assert_equal 'Chapter 1', by_slug['chapter-1'].title
      assert_equal 'Chapter 2', by_slug['chapter-2'].title
      assert_equal 'Chapter 3', by_slug['chapter-3'].title
    end
  end

  def test_creates_missing_and_destroys_extras_keeping_matched_ids
    book = Book.new
    book.yaml_import(yaml_fixture('many_find_by', doc: 0))

    ids_before = reloaded(book) do |book|
      book.book_parts.each_with_object({}) { |p, h| h[p.slug] = p.id }
    end

    book.yaml_import(yaml_fixture('many_find_by', doc: 1))

    reloaded(book) do |book|
      parts = book.book_parts.to_a
      slugs = parts.map(&:slug).sort
      assert_equal %w[chapter-1 chapter-3 chapter-4], slugs

      # chapter-1 and chapter-3 keep their ids — matched by slug, not destroyed-and-recreated.
      part_1 = parts.find { |p| p.slug == 'chapter-1' }
      part_3 = parts.find { |p| p.slug == 'chapter-3' }
      assert_equal ids_before['chapter-1'], part_1.id
      assert_equal ids_before['chapter-3'], part_3.id
      assert_equal 'Chapter 1 (updated)', part_1.title
    end
  end

  def test_export_sorts_entries_alphabetically_by_find_by_column
    book = Book.new
    book.yaml_import(yaml_fixture('many_find_by', doc: 0))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      slugs = parsed['book_parts'].map { |h| h['slug'] }

      assert_equal %w[chapter-1 chapter-2 chapter-3], slugs
    end
  end

  def test_db_duplicate_slugs_first_matched_rest_destroyed
    book = Book.create!(title: 'Ruby on Rails Tutorial')
    BookPart.create!(book_id: book.id, slug: 'chapter-1', title: 'First copy',  position: 1)
    BookPart.create!(book_id: book.id, slug: 'chapter-1', title: 'Second copy', position: 1)
    BookPart.create!(book_id: book.id, slug: 'chapter-2', title: 'Second chapter', position: 2)

    yaml = <<~YAML
      title: Ruby on Rails Tutorial
      book_parts:
        - slug: chapter-1
          title: Chapter 1 (updated)
          content: "First chapter"
          position: 1
        - slug: chapter-2
          title: Chapter 2
          content: "Second chapter"
          position: 2
    YAML
    book.yaml_import(yaml)

    reloaded(book) do |book|
      parts = book.book_parts.order(:id).to_a
      assert_equal 2, parts.size

      matched_chapter_1 = parts.find { |p| p.slug == 'chapter-1' }
      assert_equal 'Chapter 1 (updated)', matched_chapter_1.title
    end
  end

  def test_duplicate_slugs_raise_on_import
    book = Book.new
    assert_raises(YamlExporter::DuplicateKeyError) do
      book.yaml_import(yaml_fixture('many_find_by', doc: 3))
    end
  end

  def test_export_omits_empty_list_by_default
    book = Book.create!(title: 'No Parts')

    reloaded(book) do |book|
      refute YAML.safe_load(book.yaml_export).key?('book_parts')
    end
  end

  # book_parts.content is a `text` column (block scalar); title is a `string`
  # (stays inline).
  def test_export_renders_text_column_as_block_scalar_keeping_varchar_inline
    book = Book.create!(title: 'T')
    BookPart.create!(book_id: book.id, slug: 'ch-1', title: 'Chapter 1',
                     content: 'Body text here', position: 1)

    reloaded(book) do |book|
      yaml = book.yaml_export
      assert_includes yaml, 'content: |-'
      part = YAML.safe_load(yaml)['book_parts'].first
      assert_equal 'Chapter 1', part['title']
      assert_equal 'Body text here', part['content']
    end
  end

  def test_round_trip
    book = Book.new
    book.yaml_import(yaml_fixture('many_find_by', doc: 0))

    exported = reloaded(book) { |book| book.yaml_export }

    other = Book.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.book_parts.order(:slug).pluck(:slug, :title, :content, :position),
                     other.book_parts.order(:slug).pluck(:slug, :title, :content, :position)
      end
    end
  end

  def test_slugs_may_collide_across_books_and_only_own_record_is_updated
    book_a = Book.create!(title: 'Book A')
    book_b = Book.create!(title: 'Book B')

    part_a = BookPart.create!(book_id: book_a.id, slug: 'part-1', title: 'A part', content: 'A content', position: 1)
    part_b = BookPart.create!(book_id: book_b.id, slug: 'part-1', title: 'B part', content: 'B content', position: 1)

    book_b.yaml_import(yaml_fixture('many_find_by', doc: 2))

    reloaded(part_a) { |part_a| assert_equal 'A part',             part_a.title }
    reloaded(part_b) { |part_b| assert_equal 'Part One (updated)', part_b.title }
  end

  def test_importing_creates_new_row_when_slug_is_not_yet_associated_to_this_book
    book_a = Book.create!(title: 'Book A')
    book_b = Book.create!(title: 'Book B')

    BookPart.create!(book_id: book_a.id, slug: 'part-1', title: 'A part', content: 'A content', position: 1)

    # book_b has no parts yet; importing a list containing slug "part-1" should create a new row
    # rather than reuse book_a's part (find_by is scoped to this book's association).
    book_b.yaml_import(yaml_fixture('many_find_by', doc: 2))

    reloaded(book_a) do |book_a|
      reloaded(book_b) do |book_b|
        assert_equal 1, book_b.book_parts.count
        refute_equal book_a.book_parts.first.id, book_b.book_parts.first.id
        assert_equal 'Part One (updated)', book_b.book_parts.first.title
      end
    end
  end
end
