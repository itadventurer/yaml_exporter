# frozen_string_literal: true

require_relative 'test_helper'

module AttributesTestModels
  class Book < ActiveRecord::Base
    self.table_name = 'books'

    include YamlExporter

    yaml_structure do
      attributes :title, :author, :price
    end
  end
end

class AttributesTest < Minitest::Test
  Book = AttributesTestModels::Book

  def setup
    reset_test_database!
  end

  def test_import_populates_columns
    book = Book.new
    book.yaml_import(yaml_fixture('attributes', doc: 0))

    assert book.persisted?
    reloaded(book) do |book|
      assert_equal 'Ruby on Rails Tutorial', book.title
      assert_equal 'Michael Hartl', book.author
      assert_equal BigDecimal('100'), book.price
    end
  end

  def test_export_emits_declared_columns
    book = Book.create!(title: 'Ruby on Rails Tutorial', author: 'Michael Hartl', price: 100)

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export, permitted_classes: [BigDecimal])

      assert_equal 'Ruby on Rails Tutorial', parsed['title']
      assert_equal 'Michael Hartl', parsed['author']
      assert_equal BigDecimal('100'), parsed['price']
    end
  end

  def test_round_trip_produces_identical_yaml
    book = Book.new
    book.yaml_import(yaml_fixture('attributes', doc: 0))

    exported = reloaded(book) { |book| book.yaml_export }

    # Re-importing the exported YAML into a fresh instance yields the same columns.
    other = Book.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.title,  other.title
        assert_equal book.author, other.author
        assert_equal book.price,  other.price
      end
    end
  end

  def test_missing_key_resets_column_to_nil
    book = Book.create!(title: 'Ruby on Rails Tutorial', author: 'Michael Hartl', price: 100)

    book.yaml_import(yaml_fixture('attributes', doc: 1))

    reloaded(book) do |book|
      assert_equal 'Ruby on Rails Tutorial', book.title
      assert_nil book.author
      assert_nil book.price
    end
  end

  def test_null_in_yaml_resets_column_to_nil
    book = Book.create!(title: 'Ruby on Rails Tutorial', author: 'Michael Hartl', price: 100)

    book.yaml_import(yaml_fixture('attributes', doc: 2))

    reloaded(book) do |book|
      assert_equal 'Ruby on Rails Tutorial', book.title
      assert_nil book.author
      assert_nil book.price
    end
  end

  def test_undeclared_columns_raise_on_import
    book = Book.new
    assert_raises(YamlExporter::UnknownAttributeError) do
      book.yaml_import(yaml_fixture('attributes', doc: 3))
    end
  end

  def test_undeclared_columns_are_not_reset_on_import
    book = Book.create!(title: 'Ruby on Rails Tutorial', author: 'Michael Hartl', price: 100, slug: 'preset-slug')

    book.yaml_import(yaml_fixture('attributes', doc: 0))

    reloaded(book) do |book|
      assert_equal 'preset-slug', book.slug
    end
  end

  def test_null_title_raises_active_record_error
    book = Book.new
    assert_raises(ActiveRecord::ActiveRecordError) do
      book.yaml_import(yaml_fixture('attributes', doc: 4))
    end
  end
end
