# frozen_string_literal: true

require_relative 'test_helper'

# Coverage for the case where a single model declares TWO reference-style
# associations whose target class is the same (e.g. Book has both :editors
# and :coauthors, both of class `Person`).
#
# The library keys everything on association *name*, not class, so this
# should just work — these tests lock in that invariant against future
# refactors that might accidentally key on `klass` somewhere.
#
# Owned flavors (OneOwned, ManyPositional, ManyFindBy) aren't covered
# here because their code paths never dereference `klass` for routing —
# they operate purely on the association name — so role collision isn't
# a meaningful risk there.
module MultiAssocModels
  class Person < ActiveRecord::Base
    self.table_name = 'people'
  end

  # --- OneReference ----------------------------------------------------
  # Two belongs_to columns on the same table, both pointing at Person.
  module OneReferenceFlavor
    class Annotation < ActiveRecord::Base
      self.table_name = 'annotations'
      belongs_to :dedicated_to, class_name: 'MultiAssocModels::Person',
                                optional: true
      belongs_to :co_dedicatee, class_name: 'MultiAssocModels::Person',
                                optional: true
      include YamlExporter
      yaml_structure do
        attributes :title
        one :dedicated_to, find_by: :slug
        one :co_dedicatee, find_by: :slug
      end
    end
  end

  # --- ManyReference ---------------------------------------------------
  # Two HABTMs through distinct join tables, same target class.
  module ManyReferenceFlavor
    class Book < ActiveRecord::Base
      self.table_name = 'books'
      has_and_belongs_to_many :editors, class_name: 'MultiAssocModels::Person',
                                        join_table: :book_editors
      has_and_belongs_to_many :coauthors, class_name: 'MultiAssocModels::Person',
                                          join_table: :book_coauthors
      include YamlExporter
      yaml_structure do
        attributes :title
        many :editors, find_by: :slug
        many :coauthors, find_by: :slug
      end
    end
  end

  # --- ManyThrough -----------------------------------------------------
  # Two has_many-through chains both pointing at Person via distinct
  # join classes. The nuance here is that `source: :person` is the same
  # symbol on each chain — the library has to resolve source_reflection
  # against each flavor's own join class rather than cache-by-class.
  module ManyThroughFlavor
    class Editorship < ActiveRecord::Base
      self.table_name = 'editorships'
      belongs_to :person, class_name: 'MultiAssocModels::Person'
    end

    class Coauthorship < ActiveRecord::Base
      self.table_name = 'coauthorships'
      belongs_to :person, class_name: 'MultiAssocModels::Person'
    end

    class Book < ActiveRecord::Base
      self.table_name = 'books'
      has_many :editorships,
               class_name: 'MultiAssocModels::ManyThroughFlavor::Editorship',
               dependent: :destroy
      has_many :editors, through: :editorships, source: :person

      has_many :coauthorships,
               class_name: 'MultiAssocModels::ManyThroughFlavor::Coauthorship',
               dependent: :destroy
      has_many :coauthors, through: :coauthorships, source: :person

      include YamlExporter
      yaml_structure do
        attributes :title
        many :editors, through: :editorships, find_by: :slug do
          attributes :position
        end
        many :coauthors, through: :coauthorships, find_by: :slug do
          attributes :position
        end
      end
    end
  end
end

class MultiAssocTest < Minitest::Test
  def setup
    reset_test_database!
  end

  def test_one_reference_two_roles_same_target_class
    alice = MultiAssocModels::Person.create!(name: 'Alice', slug: 'alice')
    bob   = MultiAssocModels::Person.create!(name: 'Bob',   slug: 'bob')

    ann = MultiAssocModels::OneReferenceFlavor::Annotation.create!(title: 'Ann')

    ann.yaml_import(<<~YAML)
      title: To my teachers
      dedicated_to: alice
      co_dedicatee: bob
    YAML

    reloaded(ann) do |a|
      assert_equal alice.id, a.dedicated_to_id
      assert_equal bob.id,   a.co_dedicatee_id
    end

    # Swap the two roles — neither FK column must bleed into the other.
    ann.yaml_import(<<~YAML)
      title: To my teachers
      dedicated_to: bob
      co_dedicatee: alice
    YAML

    reloaded(ann) do |a|
      assert_equal bob.id,   a.dedicated_to_id
      assert_equal alice.id, a.co_dedicatee_id
    end

    # Clear one role independently.
    ann.yaml_import(<<~YAML)
      title: To my teachers
      dedicated_to: null
      co_dedicatee: alice
    YAML

    reloaded(ann) do |a|
      assert_nil a.dedicated_to_id
      assert_equal alice.id, a.co_dedicatee_id
    end

    # Round-trip: export emits both slugs in their own slots.
    ann.yaml_import(<<~YAML)
      title: To my teachers
      dedicated_to: alice
      co_dedicatee: bob
    YAML
    parsed = YAML.safe_load(reloaded(ann) { |a| a.yaml_export })
    assert_equal 'alice', parsed['dedicated_to']
    assert_equal 'bob',   parsed['co_dedicatee']
  end

  def test_many_reference_two_roles_same_target_class
    %w[alice bob carol].each do |s|
      MultiAssocModels::Person.create!(name: s.capitalize, slug: s)
    end

    book = MultiAssocModels::ManyReferenceFlavor::Book.create!(title: 'Book')

    book.yaml_import(<<~YAML)
      title: Book
      editors:
        - alice
        - bob
        - carol
      coauthors:
        - carol
    YAML

    reloaded(book) do |b|
      assert_equal %w[alice bob carol], b.editors.pluck(:slug).sort
      assert_equal %w[carol],     b.coauthors.pluck(:slug).sort
    end

    # Move people between the two roles — the two collections must not
    # contaminate each other.
    book.yaml_import(<<~YAML)
      title: Book
      editors:
        - carol
      coauthors:
        - alice
        - bob
    YAML

    reloaded(book) do |b|
      assert_equal %w[carol],     b.editors.pluck(:slug).sort
      assert_equal %w[alice bob], b.coauthors.pluck(:slug).sort
    end

    # People themselves are never destroyed.
    assert_equal 3, MultiAssocModels::Person.count

    # Export: each role gets its own list.
    parsed = YAML.safe_load(reloaded(book) { |b| b.yaml_export })
    assert_equal %w[carol],     parsed['editors']
    assert_equal %w[alice bob], parsed['coauthors']
  end

  def test_many_through_two_roles_same_target_class
    %w[alice bob carol dave].each do |s|
      MultiAssocModels::Person.create!(name: s.capitalize, slug: s)
    end

    book = MultiAssocModels::ManyThroughFlavor::Book.create!(title: 'Book')

    book.yaml_import(<<~YAML)
      title: Book
      editors:
        - slug: alice
          position: 1
        - slug: bob
          position: 2
      coauthors:
        - slug: carol
          position: 1
        - slug: dave
          position: 2
    YAML

    reloaded(book) do |b|
      assert_equal %w[alice bob],   b.editorships.map { |j| j.person.slug }.sort
      assert_equal %w[carol dave],  b.coauthorships.map { |j| j.person.slug }.sort
      # Join tables stay independent — no cross-pollution.
      assert_equal 2, b.editorships.count
      assert_equal 2, b.coauthorships.count
    end

    # Promote someone from coauthor to editor.
    book.yaml_import(<<~YAML)
      title: Book
      editors:
        - slug: alice
          position: 1
        - slug: carol
          position: 2
      coauthors:
        - slug: bob
          position: 1
        - slug: dave
          position: 2
    YAML

    reloaded(book) do |b|
      assert_equal %w[alice carol], b.editorships.map { |j| j.person.slug }.sort
      assert_equal %w[bob dave],    b.coauthorships.map { |j| j.person.slug }.sort
    end

    # Person rows untouched through all the reshuffling.
    assert_equal 4, MultiAssocModels::Person.count
  end
end
