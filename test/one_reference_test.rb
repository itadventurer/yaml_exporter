# frozen_string_literal: true

require_relative 'test_helper'

module OneReferenceTestModels
  class Publisher < ActiveRecord::Base
    self.table_name = 'publishers'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    belongs_to :publisher, class_name: 'OneReferenceTestModels::Publisher', optional: true

    include YamlExporter

    yaml_structure do
      attributes :title
      one :publisher, find_by: :slug
    end
  end
end

class OneReferenceTest < Minitest::Test
  Book = OneReferenceTestModels::Book
  Publisher = OneReferenceTestModels::Publisher

  def setup
    reset_test_database!
    @addison = Publisher.create!(name: 'Addison-Wesley', slug: 'addison-wesley')
  end

  def test_import_resolves_publisher_by_slug_and_sets_foreign_key
    book = Book.new
    book.yaml_import(yaml_fixture('one_reference', doc: 0))

    reloaded(book) do |book|
      assert_equal @addison.id, book.publisher_id
      assert_equal 'Addison-Wesley', book.publisher.name
    end
  end

  def test_unresolvable_slug_raises_record_not_found
    book = Book.new
    assert_raises(ActiveRecord::RecordNotFound) do
      book.yaml_import(yaml_fixture('one_reference', doc: 1))
    end
  end

  def test_null_value_clears_publisher_id
    book = Book.new
    book.yaml_import(yaml_fixture('one_reference', doc: 0))
    reloaded(book) { |book| assert_equal @addison.id, book.publisher_id }

    book.yaml_import(yaml_fixture('one_reference', doc: 2))

    reloaded(book) do |book|
      assert_nil book.publisher_id
      assert Publisher.exists?(@addison.id) # publisher itself left untouched
    end
  end

  def test_missing_key_clears_publisher_id
    book = Book.new
    book.yaml_import(yaml_fixture('one_reference', doc: 0))
    reloaded(book) { |book| assert_equal @addison.id, book.publisher_id }

    book.yaml_import(yaml_fixture('one_reference', doc: 3))

    reloaded(book) { |book| assert_nil book.publisher_id }
  end

  def test_slug_collision_uses_first_match
    duplicate = Publisher.create!(name: 'Addison-Wesley (dup)', slug: 'addison-wesley')
    expected_id = [@addison.id, duplicate.id].min # "first" matched — lowest id

    book = Book.new
    book.yaml_import(yaml_fixture('one_reference', doc: 0))

    reloaded(book) { |book| assert_equal expected_id, book.publisher_id }
  end

  def test_export_emits_bare_string_for_publisher_slug
    book = Book.new
    book.yaml_import(yaml_fixture('one_reference', doc: 0))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      assert_equal 'addison-wesley', parsed['publisher']
    end
  end

  def test_export_omits_publisher_when_absent_by_default
    book = Book.create!(title: 'Ruby on Rails Tutorial')

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      refute parsed.key?('publisher')
    end
  end

  def test_export_emits_null_when_publisher_absent_and_omit_nil_disabled
    book = Book.create!(title: 'Ruby on Rails Tutorial')

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export(omit_nil: false))
      assert parsed.key?('publisher')
      assert_nil parsed['publisher']
    end
  end

  def test_round_trip
    book = Book.new
    book.yaml_import(yaml_fixture('one_reference', doc: 0))

    exported = reloaded(book) { |book| book.yaml_export }
    other = Book.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.publisher_id, other.publisher_id
      end
    end
  end
end
