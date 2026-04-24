# frozen_string_literal: true

require_relative 'test_helper'

module ManyThroughTestModels
  class Reviewer < ActiveRecord::Base
    self.table_name = 'reviewers'
  end

  class BookReviewer < ActiveRecord::Base
    self.table_name = 'book_reviewers'
    belongs_to :book,     class_name: 'ManyThroughTestModels::Book'
    belongs_to :reviewer, class_name: 'ManyThroughTestModels::Reviewer'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_many :book_reviewers, class_name: 'ManyThroughTestModels::BookReviewer',
                              foreign_key: :book_id, dependent: :destroy
    has_many :reviewers, through: :book_reviewers,
                         class_name: 'ManyThroughTestModels::Reviewer'

    include YamlExporter

    yaml_structure do
      attributes :title, :price
      many :reviewers, through: :book_reviewers, find_by: :slug do
        attributes :finished
      end
    end
  end
end

class ManyThroughTest < Minitest::Test
  Book = ManyThroughTestModels::Book
  Reviewer = ManyThroughTestModels::Reviewer
  BookReviewer = ManyThroughTestModels::BookReviewer

  def setup
    reset_test_database!
    @alice = Reviewer.create!(name: 'Alice', slug: 'alice')
    @bob   = Reviewer.create!(name: 'Bob',   slug: 'bob')
  end

  def test_resolves_reviewer_by_slug_globally_not_scoped_through_join
    book = Book.new
    book.yaml_import(yaml_fixture('many_through', doc: 0))

    reloaded(book) do |book|
      assert_equal [@alice.id, @bob.id].sort, book.reviewers.pluck(:id).sort
    end
  end

  def test_block_attributes_land_on_the_join_model
    book = Book.new
    book.yaml_import(yaml_fixture('many_through', doc: 0))

    reloaded(book) do |book|
      joins_by_slug = book.book_reviewers.includes(:reviewer).each_with_object({}) do |br, h|
        h[br.reviewer.slug] = br
      end

      assert_equal true,  joins_by_slug['alice'].finished
      assert_equal false, joins_by_slug['bob'].finished
    end
  end

  def test_find_or_create_on_join_does_not_duplicate_rows
    book = Book.new
    book.yaml_import(yaml_fixture('many_through', doc: 0))
    before_ids = reloaded(book) { |book| book.book_reviewers.pluck(:id).sort }

    # Re-import identical data: the existing joins should be kept, not replaced.
    book.yaml_import(yaml_fixture('many_through', doc: 0))

    reloaded(book) do |book|
      assert_equal before_ids, book.book_reviewers.pluck(:id).sort
    end
  end

  def test_removed_reviewers_destroy_only_join_rows
    book = Book.new
    book.yaml_import(yaml_fixture('many_through', doc: 0))
    reloaded(book) { |book| assert_equal 2, book.book_reviewers.count }

    book.yaml_import(yaml_fixture('many_through', doc: 1))

    reloaded(book) do |book|
      assert_equal [@bob.id], book.reviewers.pluck(:id)
      assert Reviewer.exists?(@alice.id) # reviewer itself left untouched
      assert_equal 1, book.book_reviewers.count

      assert_equal true, book.book_reviewers.find_by(reviewer_id: @bob.id).finished
    end
  end

  def test_unresolvable_slug_raises_record_not_found
    book = Book.new
    assert_raises(ActiveRecord::RecordNotFound) do
      book.yaml_import(yaml_fixture('many_through', doc: 2))
    end
  end

  def test_round_trip
    book = Book.new
    book.yaml_import(yaml_fixture('many_through', doc: 0))

    exported = reloaded(book) { |book| book.yaml_export }

    other = Book.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.reviewers.pluck(:id).sort, other.reviewers.pluck(:id).sort
        assert_equal book.book_reviewers.order(:reviewer_id).pluck(:finished),
                     other.book_reviewers.order(:reviewer_id).pluck(:finished)
      end
    end
  end
end
