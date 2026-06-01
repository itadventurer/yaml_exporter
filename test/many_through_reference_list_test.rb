# frozen_string_literal: true

require_relative 'test_helper'

# `many :assoc, through: :join, find_by: :col` with NO block (or an empty
# one): the YAML is a bare list of find_by values, exactly like a plain
# reference list, but routed through a join model. positioned_by: derives the
# join's position column from the YAML order.
module ManyThroughReferenceListTestModels
  class Reviewer < ActiveRecord::Base
    self.table_name = 'reviewers'
  end

  class BookReviewer < ActiveRecord::Base
    self.table_name = 'book_reviewers'
    belongs_to :book,     class_name: 'ManyThroughReferenceListTestModels::Book'
    belongs_to :reviewer, class_name: 'ManyThroughReferenceListTestModels::Reviewer'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_many :book_reviewers, class_name: 'ManyThroughReferenceListTestModels::BookReviewer',
                              foreign_key: :book_id, dependent: :destroy
    has_many :reviewers, through: :book_reviewers,
                         class_name: 'ManyThroughReferenceListTestModels::Reviewer'

    include YamlExporter

    yaml_structure do
      attributes :title, :price
      # No block: bare reference list. positioned_by drives the join order.
      many :reviewers, through: :book_reviewers, find_by: :slug, positioned_by: :position
    end
  end
end

class ManyThroughReferenceListTest < Minitest::Test
  Book = ManyThroughReferenceListTestModels::Book
  Reviewer = ManyThroughReferenceListTestModels::Reviewer

  def setup
    reset_test_database!
    @alice = Reviewer.create!(name: 'Alice', slug: 'alice')
    @bob   = Reviewer.create!(name: 'Bob',   slug: 'bob')
  end

  def import_yaml(reviewers)
    <<~YAML
      title: Ruby on Rails Tutorial
      price: 38.0
      reviewers:
      #{reviewers.map { |s| "  - #{s}" }.join("\n")}
    YAML
  end

  def test_import_resolves_bare_strings_to_existing_reviewers
    book = Book.new
    book.yaml_import(import_yaml(%w[alice bob]))

    reloaded(book) do |book|
      assert_equal [@alice.id, @bob.id].sort, book.reviewers.pluck(:id).sort
      # Join rows were created; no extra attributes consumed.
      assert_equal 2, book.book_reviewers.count
    end
  end

  def test_does_not_auto_create_referenced_records
    assert_equal 2, Reviewer.count
    book = Book.new
    book.yaml_import(import_yaml(%w[alice bob]))
    assert_equal 2, Reviewer.count
  end

  def test_position_is_derived_from_yaml_order
    book = Book.new
    book.yaml_import(import_yaml(%w[bob alice]))

    reloaded(book) do |book|
      positions = book.book_reviewers.includes(:reviewer).each_with_object({}) do |br, h|
        h[br.reviewer.slug] = br.position
      end
      assert_equal({ 'bob' => 1, 'alice' => 2 }, positions)
    end
  end

  def test_unresolvable_value_raises_record_not_found
    book = Book.new
    assert_raises(ActiveRecord::RecordNotFound) do
      book.yaml_import(import_yaml(%w[nobody]))
    end
  end

  def test_export_emits_bare_strings_ordered_by_position
    book = Book.new
    book.yaml_import(import_yaml(%w[bob alice]))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      # positioned_by wins: export order follows position (bob=1, alice=2).
      assert_equal %w[bob alice], parsed['reviewers']
    end
  end

  def test_removal_only_drops_join_rows_not_the_reviewer
    book = Book.new
    book.yaml_import(import_yaml(%w[alice bob]))
    reloaded(book) { |book| assert_equal 2, book.book_reviewers.count }

    book.yaml_import(import_yaml(%w[alice]))

    reloaded(book) do |book|
      assert_equal [@alice.id], book.reviewers.pluck(:id)
      assert_equal 1, book.book_reviewers.count
      assert Reviewer.exists?(@bob.id) # reviewer row untouched
    end
  end

  def test_reimport_keeps_existing_join_rows
    book = Book.new
    book.yaml_import(import_yaml(%w[alice bob]))
    before_ids = reloaded(book) { |book| book.book_reviewers.pluck(:id).sort }

    book.yaml_import(import_yaml(%w[alice bob]))

    reloaded(book) do |book|
      assert_equal before_ids, book.book_reviewers.pluck(:id).sort
    end
  end

  def test_round_trip
    book = Book.new
    book.yaml_import(import_yaml(%w[bob alice]))

    exported = reloaded(book) { |book| book.yaml_export }

    other = Book.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.reviewers.pluck(:id).sort, other.reviewers.pluck(:id).sort
        assert_equal book.book_reviewers.order(:position).map { |br| br.reviewer.slug },
                     other.book_reviewers.order(:position).map { |br| br.reviewer.slug }
      end
    end
  end

end
