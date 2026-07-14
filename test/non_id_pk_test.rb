# frozen_string_literal: true

require_relative 'test_helper'

# Coverage for models whose primary key is NOT `:id`. The library must
# never hard-code `:id` anywhere — neither for FK assignment, nor for
# ordering, nor for destroy-missing bookkeeping.
#
# Chapter uses :slug as its PK; Genre uses :code (and has a distinct
# :name column so find_by can diverge from the PK).
module NonIdPkModels
  class Chapter < ActiveRecord::Base
    self.table_name = 'chapters'
    self.primary_key = :slug
  end

  class Genre < ActiveRecord::Base
    self.table_name = 'genres'
    self.primary_key = :code
  end

  # Join model for the has_many :through flavor. Lives outside the
  # per-test Book modules because the `source: :genre` on Book points
  # to this class's belongs_to reflection.
  class GenreAssignment < ActiveRecord::Base
    self.table_name = 'genre_assignments'
    belongs_to :genre, class_name: 'NonIdPkModels::Genre',
                       foreign_key: :genre_code, primary_key: :code
  end

  # One Book subclass per node-type test — keeps yaml_structure isolated
  # and avoids having one giant structure that every test has to satisfy.
  module OneOwnedFlavor
    class Book < ActiveRecord::Base
      self.table_name = 'books'
      has_one :chapter, class_name: 'NonIdPkModels::Chapter',
                        foreign_key: :book_id, dependent: :destroy
      include YamlExporter
      yaml_structure do
        attributes :title
        one :chapter do
          attributes :slug, :title, :content
        end
      end
    end
  end

  module OneReferenceFlavor
    class Book < ActiveRecord::Base
      self.table_name = 'books'
      # The belongs_to explicitly points at Genre's :code column — Rails
      # would otherwise assume :id. This is exactly what the library has
      # to handle via the association setter instead of `fk = target.id`.
      belongs_to :primary_genre, class_name: 'NonIdPkModels::Genre',
                                 foreign_key: :primary_genre_code,
                                 primary_key: :code, optional: true
      include YamlExporter
      yaml_structure do
        attributes :title
        one :primary_genre, find_by: :name
      end
    end
  end

  module ManyPositionalFlavor
    class Book < ActiveRecord::Base
      self.table_name = 'books'
      has_many :chapters, class_name: 'NonIdPkModels::Chapter',
                          foreign_key: :book_id, dependent: :destroy
      include YamlExporter
      yaml_structure do
        attributes :title
        many :chapters do
          attributes :slug, :title, :content
        end
      end
    end
  end

  module ManyFindByFlavor
    class Book < ActiveRecord::Base
      self.table_name = 'books'
      has_many :chapters, class_name: 'NonIdPkModels::Chapter',
                          foreign_key: :book_id, dependent: :destroy
      include YamlExporter
      yaml_structure do
        attributes :title
        # find_by column IS the PK here — a common real-world shape.
        many :chapters, find_by: :slug do
          attributes :title, :content
        end
      end
    end
  end

  module ManyReferenceFlavor
    class Book < ActiveRecord::Base
      self.table_name = 'books'
      has_and_belongs_to_many :genres, class_name: 'NonIdPkModels::Genre',
                                       join_table: :books_genres,
                                       foreign_key: :book_id,
                                       association_foreign_key: :genre_code
      include YamlExporter
      yaml_structure do
        attributes :title
        many :genres, find_by: :name
      end
    end
  end

  module ManyThroughFlavor
    class Book < ActiveRecord::Base
      self.table_name = 'books'
      has_many :genre_assignments,
               class_name: 'NonIdPkModels::GenreAssignment',
               foreign_key: :book_id, dependent: :destroy
      has_many :genres, through: :genre_assignments, source: :genre
      include YamlExporter
      yaml_structure do
        attributes :title
        many :genres, through: :genre_assignments, find_by: :name do
          attributes :position
        end
      end
    end
  end
end

class NonIdPkTest < Minitest::Test
  def setup
    reset_test_database!
  end

  def test_one_owned_with_non_id_pk_child
    book = NonIdPkModels::OneOwnedFlavor::Book.create!(title: 'Book')

    book.yaml_import(<<~YAML)
      title: Refactoring
      chapter:
        slug: intro
        title: Introduction
        content: The basics.
    YAML

    reloaded(book) do |b|
      assert_equal 'intro', b.chapter.slug
      assert_equal 'Introduction', b.chapter.title
    end

    # Same slug, updated content — in-place UPDATE against a non-id PK.
    book.yaml_import(<<~YAML)
      title: Refactoring
      chapter:
        slug: intro
        title: Introduction (rev 2)
        content: The basics, revised.
    YAML

    reloaded(book) do |b|
      assert_equal 'Introduction (rev 2)', b.chapter.title
    end
    assert_equal 1, NonIdPkModels::Chapter.where(book_id: book.id).count

    # Null destroys the child — destroy! has to issue a DELETE keyed on
    # :slug, not :id.
    book.yaml_import("title: Refactoring\nchapter: null\n")
    reloaded(book) { |b| assert_nil b.chapter }
    assert_equal 0, NonIdPkModels::Chapter.where(book_id: book.id).count

    # Export round-trip.
    book.yaml_import(<<~YAML)
      title: Refactoring
      chapter:
        slug: afterword
        title: Afterword
        content: Wrapping up.
    YAML
    parsed = YAML.safe_load(reloaded(book) { |b| b.yaml_export })
    assert_equal 'afterword', parsed['chapter']['slug']
    assert_equal 'Afterword', parsed['chapter']['title']
  end

  def test_one_reference_with_non_id_pk_target
    NonIdPkModels::Genre.create!(code: 'FIC', name: 'Fiction')
    NonIdPkModels::Genre.create!(code: 'NF',  name: 'Nonfiction')

    book = NonIdPkModels::OneReferenceFlavor::Book.create!(title: 'Book')

    book.yaml_import("title: Ex\nprimary_genre: Fiction\n")
    reloaded(book) do |b|
      # The FK column on books now holds the target's :code, not an id.
      assert_equal 'FIC', b.primary_genre_code
      assert_equal 'Fiction', b.primary_genre.name
    end

    book.yaml_import("title: Ex\nprimary_genre: Nonfiction\n")
    reloaded(book) { |b| assert_equal 'NF', b.primary_genre_code }

    book.yaml_import("title: Ex\nprimary_genre: null\n")
    reloaded(book) do |b|
      assert_nil b.primary_genre_code
      assert_nil b.primary_genre
    end

    # Export emits :name (the find_by column), never the :code.
    book.yaml_import("title: Ex\nprimary_genre: Fiction\n")
    parsed = YAML.safe_load(reloaded(book) { |b| b.yaml_export })
    assert_equal 'Fiction', parsed['primary_genre']
  end

  def test_many_positional_with_non_id_pk_child
    book = NonIdPkModels::ManyPositionalFlavor::Book.create!(title: 'Book')

    book.yaml_import(<<~YAML)
      title: Many
      chapters:
        - slug: a
          title: A-1
          content: first
        - slug: b
          title: B-1
          content: second
        - slug: c
          title: C-1
          content: third
    YAML

    reloaded(book) do |b|
      assert_equal 3, b.chapters.count
      assert_equal %w[a b c], b.chapters.order(:slug).pluck(:slug)
    end

    # Shrink: drop the third entry. Positional destroy-missing has to
    # DELETE keyed by slug (the child PK), not id.
    book.yaml_import(<<~YAML)
      title: Many
      chapters:
        - slug: a
          title: A-2
          content: first v2
        - slug: b
          title: B-2
          content: second v2
    YAML

    reloaded(book) do |b|
      rows = b.chapters.order(:slug).to_a
      assert_equal %w[a b], rows.map(&:slug)
      assert_equal 'A-2', rows[0].title
    end
    assert_equal 0, NonIdPkModels::Chapter.where(book_id: book.id, slug: 'c').count
  end

  def test_many_find_by_with_non_id_pk_child
    book = NonIdPkModels::ManyFindByFlavor::Book.create!(title: 'Book')

    book.yaml_import(<<~YAML)
      title: By-slug
      chapters:
        - slug: intro
          title: Intro
          content: intro body
        - slug: middle
          title: Middle
          content: mid body
    YAML

    reloaded(book) do |b|
      assert_equal %w[intro middle], b.chapters.order(:slug).pluck(:slug)
    end

    # Reorder + update one + add one + drop one.
    book.yaml_import(<<~YAML)
      title: By-slug
      chapters:
        - slug: intro
          title: Intro (updated)
          content: intro body v2
        - slug: epilogue
          title: Epilogue
          content: end
    YAML

    reloaded(book) do |b|
      assert_equal %w[epilogue intro], b.chapters.order(:slug).pluck(:slug)
      assert_equal 'Intro (updated)', b.chapters.find_by(slug: 'intro').title
    end

    # Export order is by the find_by column, not by id.
    parsed = YAML.safe_load(reloaded(book) { |b| b.yaml_export })
    assert_equal %w[epilogue intro], parsed['chapters'].map { |c| c['slug'] }
  end

  def test_many_reference_with_non_id_pk_target
    codes = { 'Fiction' => 'FIC', 'Nonfiction' => 'NF', 'Poetry' => 'POE' }
    codes.each { |name, code| NonIdPkModels::Genre.create!(code: code, name: name) }

    book = NonIdPkModels::ManyReferenceFlavor::Book.create!(title: 'Book')

    book.yaml_import(<<~YAML)
      title: Shelf
      genres:
        - Fiction
        - Poetry
    YAML

    reloaded(book) do |b|
      assert_equal %w[FIC POE], b.genres.pluck(:code).sort
    end

    book.yaml_import(<<~YAML)
      title: Shelf
      genres:
        - Nonfiction
        - Poetry
    YAML

    reloaded(book) do |b|
      assert_equal %w[NF POE], b.genres.pluck(:code).sort
    end

    book.yaml_import("title: Shelf\ngenres: []\n")
    reloaded(book) { |b| assert_empty b.genres }

    # Target rows are never touched, regardless of PK shape.
    assert_equal 3, NonIdPkModels::Genre.count
  end

  def test_many_through_with_non_id_pk_target
    codes = { 'Fiction' => 'FIC', 'Nonfiction' => 'NF', 'Poetry' => 'POE' }
    codes.each { |name, code| NonIdPkModels::Genre.create!(code: code, name: name) }

    book = NonIdPkModels::ManyThroughFlavor::Book.create!(title: 'Book')

    book.yaml_import(<<~YAML)
      title: Shelf
      genres:
        - name: Fiction
          position: 1
        - name: Poetry
          position: 2
    YAML

    reloaded(book) do |b|
      pairs = b.genre_assignments.map { |ga| [ga.genre.name, ga.position] }
      assert_includes pairs, ['Fiction', 1]
      assert_includes pairs, ['Poetry', 2]
      # Join row's `genre_code` (FK with custom PK on the target) is set.
      assert_equal %w[FIC POE], b.genre_assignments.pluck(:genre_code).sort
    end

    # Drop one — join row is destroyed; Genre stays.
    book.yaml_import(<<~YAML)
      title: Shelf
      genres:
        - name: Poetry
          position: 1
    YAML

    reloaded(book) do |b|
      names = b.genre_assignments.map { |ga| ga.genre.name }
      assert_equal ['Poetry'], names
    end
    assert_equal 3, NonIdPkModels::Genre.count
  end
end
