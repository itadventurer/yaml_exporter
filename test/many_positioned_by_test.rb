# frozen_string_literal: true

require_relative 'test_helper'

module ManyPositionedByTestModels
  class BookPart < ActiveRecord::Base
    self.table_name = 'book_parts'
    belongs_to :book, class_name: 'ManyPositionedByTestModels::Book', optional: true
    belongs_to :positional_book, class_name: 'ManyPositionedByTestModels::PositionalBook',
                                 foreign_key: :book_id, optional: true
    belongs_to :slugged_book, class_name: 'ManyPositionedByTestModels::SluggedBook',
                              foreign_key: :book_id, optional: true
  end

  class Reviewer < ActiveRecord::Base
    self.table_name = 'reviewers'
  end

  class BookReviewer < ActiveRecord::Base
    self.table_name = 'book_reviewers'
    belongs_to :book,     class_name: 'ManyPositionedByTestModels::ThroughBook', optional: true
    belongs_to :reviewer, class_name: 'ManyPositionedByTestModels::Reviewer'
  end

  # Variant A: positional (no find_by) + positioned_by.
  class PositionalBook < ActiveRecord::Base
    self.table_name = 'books'
    has_many :book_parts, class_name: 'ManyPositionedByTestModels::BookPart',
                          foreign_key: :book_id, dependent: :destroy

    include YamlExporter

    yaml_structure do
      attributes :title
      many :book_parts, positioned_by: :position do
        attributes :title, :content
      end
    end
  end

  # Variant B: find_by + positioned_by.
  class SluggedBook < ActiveRecord::Base
    self.table_name = 'books'
    has_many :book_parts, class_name: 'ManyPositionedByTestModels::BookPart',
                          foreign_key: :book_id, dependent: :destroy

    include YamlExporter

    yaml_structure do
      attributes :title
      many :book_parts, find_by: :slug, positioned_by: :position do
        attributes :title, :content
      end
    end
  end

  # Variant C: through: + find_by + positioned_by (position on the join model).
  class ThroughBook < ActiveRecord::Base
    self.table_name = 'books'
    has_many :book_reviewers, class_name: 'ManyPositionedByTestModels::BookReviewer',
                              foreign_key: :book_id, dependent: :destroy
    has_many :reviewers, through: :book_reviewers,
                         class_name: 'ManyPositionedByTestModels::Reviewer'

    include YamlExporter

    yaml_structure do
      attributes :title, :price
      many :reviewers, through: :book_reviewers, find_by: :slug, positioned_by: :position do
        attributes :finished
      end
    end
  end
end

class ManyPositionedByTest < Minitest::Test
  BookPart = ManyPositionedByTestModels::BookPart
  Reviewer = ManyPositionedByTestModels::Reviewer
  BookReviewer = ManyPositionedByTestModels::BookReviewer
  PositionalBook = ManyPositionedByTestModels::PositionalBook
  SluggedBook = ManyPositionedByTestModels::SluggedBook
  ThroughBook = ManyPositionedByTestModels::ThroughBook

  def setup
    reset_test_database!
  end

  # ------------------------------------------------------------------
  # Variant A: positional + positioned_by
  # ------------------------------------------------------------------

  def test_variant_a_import_derives_1_based_position_from_array_index
    book = PositionalBook.new
    book.yaml_import(yaml_fixture('many_positioned_by', doc: 0))

    reloaded(book) do |book|
      parts = book.book_parts.order(:id).to_a
      assert_equal [1, 2, 3], parts.map(&:position)
      assert_equal ['Chapter 1', 'Chapter 2', 'Chapter 3'], parts.map(&:title)
    end
  end

  def test_variant_a_export_sorts_by_position_and_omits_column
    book = PositionalBook.new
    book.yaml_import(yaml_fixture('many_positioned_by', doc: 0))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      assert_equal ['Chapter 1', 'Chapter 2', 'Chapter 3'],
                   parsed['book_parts'].map { |h| h['title'] }
      refute parsed['book_parts'].any? { |h| h.key?('position') },
             'exported hash must not carry the positioned_by column'
    end
  end

  def test_variant_a_db_drift_is_rewritten_to_1_to_n
    book = PositionalBook.create!(title: 'Ruby on Rails Tutorial')
    # Seed drifted positions directly: gaps, duplicates, nil.
    BookPart.create!(book_id: book.id, title: 'Chapter 1', content: 'First',  position: 7)
    BookPart.create!(book_id: book.id, title: 'Chapter 2', content: 'Second', position: nil)
    BookPart.create!(book_id: book.id, title: 'Chapter 3', content: 'Third',  position: 7)

    book.yaml_import(yaml_fixture('many_positioned_by', doc: 0))

    reloaded(book) do |book|
      positions = book.book_parts.order(:id).pluck(:position)
      assert_equal [1, 2, 3], positions
    end
  end

  def test_variant_a_round_trip
    book = PositionalBook.new
    book.yaml_import(yaml_fixture('many_positioned_by', doc: 0))

    exported = reloaded(book) { |book| book.yaml_export }
    other = PositionalBook.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.book_parts.order(:position).pluck(:title, :content, :position),
                     other.book_parts.order(:position).pluck(:title, :content, :position)
      end
    end
  end

  # ------------------------------------------------------------------
  # Variant B: find_by + positioned_by
  # ------------------------------------------------------------------

  def test_variant_b_import_derives_position_from_array_index
    book = SluggedBook.new
    book.yaml_import(yaml_fixture('many_positioned_by', doc: 1))

    reloaded(book) do |book|
      by_slug = book.book_parts.each_with_object({}) { |p, h| h[p.slug] = p }
      assert_equal 1, by_slug['chapter-1'].position
      assert_equal 2, by_slug['chapter-2'].position
      assert_equal 3, by_slug['chapter-3'].position
    end
  end

  def test_variant_b_reordering_updates_position_on_existing_rows
    book = SluggedBook.new
    book.yaml_import(yaml_fixture('many_positioned_by', doc: 1))
    ids_before = reloaded(book) do |book|
      book.book_parts.each_with_object({}) { |p, h| h[p.slug] = p.id }
    end

    book.yaml_import(yaml_fixture('many_positioned_by', doc: 2))

    reloaded(book) do |book|
      by_slug = book.book_parts.each_with_object({}) { |p, h| h[p.slug] = p }
      # identity by slug is preserved — ids don't change on reorder
      assert_equal ids_before['chapter-1'], by_slug['chapter-1'].id
      assert_equal ids_before['chapter-2'], by_slug['chapter-2'].id
      assert_equal ids_before['chapter-3'], by_slug['chapter-3'].id

      # positions follow the new list order
      assert_equal 1, by_slug['chapter-3'].position
      assert_equal 2, by_slug['chapter-1'].position
      assert_equal 3, by_slug['chapter-2'].position
    end
  end

  def test_variant_b_export_sorts_by_position_and_omits_column
    book = SluggedBook.new
    book.yaml_import(yaml_fixture('many_positioned_by', doc: 2))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      slugs = parsed['book_parts'].map { |h| h['slug'] }
      assert_equal %w[chapter-3 chapter-1 chapter-2], slugs
      refute parsed['book_parts'].any? { |h| h.key?('position') }
    end
  end

  def test_variant_b_db_drift_is_rewritten
    book = SluggedBook.create!(title: 'Ruby on Rails Tutorial')
    BookPart.create!(book_id: book.id, slug: 'chapter-1', title: 'x', content: 'x', position: nil)
    BookPart.create!(book_id: book.id, slug: 'chapter-2', title: 'x', content: 'x', position: 99)
    BookPart.create!(book_id: book.id, slug: 'chapter-3', title: 'x', content: 'x', position: 99)

    book.yaml_import(yaml_fixture('many_positioned_by', doc: 1))

    reloaded(book) do |book|
      by_slug = book.book_parts.each_with_object({}) { |p, h| h[p.slug] = p.position }
      assert_equal({ 'chapter-1' => 1, 'chapter-2' => 2, 'chapter-3' => 3 }, by_slug)
    end
  end

  def test_variant_b_yaml_entry_with_positioned_column_is_rejected
    book = SluggedBook.new
    assert_raises(YamlExporter::UnknownAttributeError) do
      book.yaml_import(yaml_fixture('many_positioned_by', doc: 4))
    end
  end

  def test_variant_b_round_trip
    book = SluggedBook.new
    book.yaml_import(yaml_fixture('many_positioned_by', doc: 2))

    exported = reloaded(book) { |book| book.yaml_export }
    other = SluggedBook.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.book_parts.order(:position).pluck(:slug, :position),
                     other.book_parts.order(:position).pluck(:slug, :position)
      end
    end
  end

  def test_gapped_and_out_of_order_positions_compact_through_round_trip
    # Seed drifted positions directly. positioned_by is DSL-owned, so these
    # exact values (a gap at 2, and the top two inserted out of order:
    # c=5 before d=4) cannot be expressed in YAML — they only arise in the DB.
    #   insertion/id order: a, b, c, d
    #   positions:          1, 3, 5, 4
    book = SluggedBook.create!(title: 'Ruby on Rails Tutorial')
    a = BookPart.create!(book_id: book.id, slug: 'a', title: 'A', content: 'A', position: 1)
    b = BookPart.create!(book_id: book.id, slug: 'b', title: 'B', content: 'B', position: 3)
    c = BookPart.create!(book_id: book.id, slug: 'c', title: 'C', content: 'C', position: 5)
    d = BookPart.create!(book_id: book.id, slug: 'd', title: 'D', content: 'D', position: 4)

    # Export sorts by position ASC, normalizing the gap and the 5/4 swap into
    # list order: a(1), b(3), d(4), c(5).
    exported = reloaded(book) { |bk| bk.yaml_export }
    assert_equal %w[a b d c], YAML.safe_load(exported)['book_parts'].map { |h| h['slug'] }

    # Re-import the export. find_by keeps identity (ids unchanged); positioned_by
    # re-derives the column from the 1-based array index, closing the gap to 1..N.
    book.yaml_import(exported)

    reloaded(book) do |bk|
      by_pos = bk.book_parts.order(:position).each_with_object({}) { |p, h| h[p.position] = p }
      assert_equal a.id, by_pos[1].id  # 'a' stays first
      assert_equal b.id, by_pos[2].id  # 'b' moves 3 -> 2 (gap at 2 closed)
      assert_equal d.id, by_pos[3].id  # 'd' (was 4) now precedes 'c' (was 5)
      assert_equal c.id, by_pos[4].id  # 'c' (was 5) lands last
      assert_equal [1, 2, 3, 4], bk.book_parts.order(:position).pluck(:position)
    end
  end

  # ------------------------------------------------------------------
  # Variant C: through: + find_by + positioned_by (position on join)
  # ------------------------------------------------------------------

  def test_variant_c_position_lives_on_join_and_is_derived_from_array_index
    Reviewer.create!(name: 'Alice', slug: 'alice')
    Reviewer.create!(name: 'Bob',   slug: 'bob')

    book = ThroughBook.new
    book.yaml_import(yaml_fixture('many_positioned_by', doc: 3))

    reloaded(book) do |book|
      joins_by_slug = book.book_reviewers.includes(:reviewer).each_with_object({}) do |br, h|
        h[br.reviewer.slug] = br
      end
      # order in YAML: bob, alice (1, 2)
      assert_equal 1, joins_by_slug['bob'].position
      assert_equal 2, joins_by_slug['alice'].position
    end
  end

  def test_variant_c_export_sorts_by_join_position_and_omits_column
    Reviewer.create!(name: 'Alice', slug: 'alice')
    Reviewer.create!(name: 'Bob',   slug: 'bob')

    book = ThroughBook.new
    book.yaml_import(yaml_fixture('many_positioned_by', doc: 3))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      assert_equal %w[bob alice], parsed['reviewers'].map { |h| h['slug'] }
      refute parsed['reviewers'].any? { |h| h.key?('position') }
    end
  end

  def test_variant_c_round_trip
    Reviewer.create!(name: 'Alice', slug: 'alice')
    Reviewer.create!(name: 'Bob',   slug: 'bob')

    book = ThroughBook.new
    book.yaml_import(yaml_fixture('many_positioned_by', doc: 3))

    exported = reloaded(book) { |book| book.yaml_export }
    other = ThroughBook.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.book_reviewers.order(:position).pluck(:reviewer_id, :finished, :position),
                     other.book_reviewers.order(:position).pluck(:reviewer_id, :finished, :position)
      end
    end
  end

  # ------------------------------------------------------------------
  # Cross-variant precedence: positioned_by > find_by > SQL order
  # ------------------------------------------------------------------

  def test_export_ordering_precedence_positioned_by_wins_over_find_by
    # SluggedBook has both find_by: :slug and positioned_by: :position.
    # Import in slug-alphabetical order, but assign positions differently.
    book = SluggedBook.new
    book.yaml_import(yaml_fixture('many_positioned_by', doc: 1))

    # Swap positions directly in the DB so position order diverges from slug order.
    reloaded(book) do |book|
      parts = book.book_parts.order(:slug).to_a
      parts[0].update!(position: 3)
      parts[1].update!(position: 1)
      parts[2].update!(position: 2)
    end

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      slugs = parsed['book_parts'].map { |h| h['slug'] }
      # positioned_by wins: list is sorted by position ASC, not by slug.
      assert_equal %w[chapter-2 chapter-3 chapter-1], slugs
    end
  end
end
