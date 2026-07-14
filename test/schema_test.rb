# frozen_string_literal: true

require_relative 'test_helper'

module SchemaTestModels
  class BookPart < ActiveRecord::Base
    self.table_name = 'book_parts'
    belongs_to :book, class_name: 'SchemaTestModels::Book', optional: true
  end

  class BookDetail < ActiveRecord::Base
    self.table_name = 'book_details'
    belongs_to :book, class_name: 'SchemaTestModels::Book', optional: true
  end

  class Author < ActiveRecord::Base
    self.table_name = 'authors'
  end

  class Publisher < ActiveRecord::Base
    self.table_name = 'publishers'
  end

  class Reviewer < ActiveRecord::Base
    self.table_name = 'reviewers'
  end

  class BookReviewer < ActiveRecord::Base
    self.table_name = 'book_reviewers'
    belongs_to :book, class_name: 'SchemaTestModels::Book', optional: true
    belongs_to :reviewer, class_name: 'SchemaTestModels::Reviewer'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_many :book_parts,     class_name: 'SchemaTestModels::BookPart',     foreign_key: :book_id, dependent: :destroy
    has_one  :book_detail,    class_name: 'SchemaTestModels::BookDetail',   foreign_key: :book_id, dependent: :destroy
    has_and_belongs_to_many :authors, class_name: 'SchemaTestModels::Author', join_table: 'authors_books'
    belongs_to :publisher, class_name: 'SchemaTestModels::Publisher', optional: true
    has_many :book_reviewers, class_name: 'SchemaTestModels::BookReviewer', foreign_key: :book_id, dependent: :destroy
    has_many :reviewers, through: :book_reviewers, class_name: 'SchemaTestModels::Reviewer'

    include YamlExporter

    yaml_structure do
      attributes :title, :price
      many :book_parts, find_by: :slug, positioned_by: :position do
        attributes :title, :content
      end
      one :book_detail do
        attributes :summary, :publication_year
      end
      many :authors, find_by: :slug
      one :publisher, find_by: :slug
      many :reviewers, through: :book_reviewers, find_by: :slug do
        attributes :finished
      end
    end
  end
end

class SchemaTest < Minitest::Test
  Book = SchemaTestModels::Book

  def setup
    reset_test_database!
  end

  def test_yaml_schema_is_json_schema_like_hash
    schema = Book.yaml_schema

    assert_kind_of Hash, schema
    assert_equal 'object', schema[:type]
    assert_kind_of Hash, schema[:properties]
  end

  def test_attributes_become_properties_on_root
    props = Book.yaml_schema[:properties]
    assert props.key?(:title)
    assert props.key?(:price)
  end

  def test_string_attribute_infers_string_type
    assert_equal 'string', Book.yaml_schema[:properties][:title][:type]
  end

  def test_float_attribute_infers_number_type
    assert_equal 'number', Book.yaml_schema[:properties][:price][:type]
  end

  def test_integer_attribute_infers_integer_type
    detail_props = Book.yaml_schema[:properties][:book_detail][:properties]
    assert_equal 'integer', detail_props[:publication_year][:type]
  end

  def test_text_attribute_infers_string_type
    detail_props = Book.yaml_schema[:properties][:book_detail][:properties]
    assert_equal 'string', detail_props[:summary][:type]
  end

  def test_boolean_attribute_infers_boolean_type
    reviewers_item_props = Book.yaml_schema[:properties][:reviewers][:items][:properties]
    assert_equal 'boolean', reviewers_item_props[:finished][:type]
  end

  def test_one_find_by_type_is_looked_up_on_target
    # publishers.slug is a string column → type resolves via target_class.
    assert_equal 'string', Book.yaml_schema[:properties][:publisher][:type]
  end

  def test_many_find_by_type_is_looked_up_on_target
    # book_parts.slug on the target, not hardcoded.
    parts_item_props = Book.yaml_schema[:properties][:book_parts][:items][:properties]
    assert_equal 'string', parts_item_props[:slug][:type]
  end

  def test_many_reference_items_type_is_looked_up_on_target
    # authors.slug → string, via target_class lookup (not hardcoded).
    authors = Book.yaml_schema[:properties][:authors]
    assert_equal 'string', authors[:items][:type]
  end

  def test_through_find_by_type_is_looked_up_on_target_not_join
    # reviewers.slug resolves against Reviewer (target), not BookReviewer (join).
    reviewers_item_props = Book.yaml_schema[:properties][:reviewers][:items][:properties]
    assert_equal 'string', reviewers_item_props[:slug][:type]
  end

  def test_one_with_block_becomes_nested_object_schema
    detail = Book.yaml_schema[:properties][:book_detail]
    assert_equal 'object', detail[:type]
    assert detail[:properties].key?(:summary)
    assert detail[:properties].key?(:publication_year)
  end

  def test_one_with_find_by_becomes_string
    pub = Book.yaml_schema[:properties][:publisher]
    assert_equal 'string', pub[:type]
  end

  def test_many_with_block_becomes_array_of_objects
    parts = Book.yaml_schema[:properties][:book_parts]
    assert_equal 'array', parts[:type]
    assert_equal 'object', parts[:items][:type]
    assert parts[:items][:properties].key?(:slug)
    assert parts[:items][:properties].key?(:title)
    assert parts[:items][:properties].key?(:content)
  end

  def test_many_with_find_by_alone_becomes_array_of_strings
    authors = Book.yaml_schema[:properties][:authors]
    assert_equal 'array', authors[:type]
    assert_equal 'string', authors[:items][:type]
  end

  def test_positioned_by_column_is_absent_from_item_schema
    parts_items = Book.yaml_schema[:properties][:book_parts][:items]
    refute parts_items[:properties].key?(:position),
           'positioned_by column must be omitted — the DSL derives it'
  end

  def test_through_variant_describes_join_attributes
    reviewers = Book.yaml_schema[:properties][:reviewers]
    assert_equal 'array', reviewers[:type]
    assert_equal 'object', reviewers[:items][:type]
    assert reviewers[:items][:properties].key?(:slug)
    assert reviewers[:items][:properties].key?(:finished)
  end

  def test_invalid_yaml_raises_on_import_with_descriptive_message
    yaml = <<~YAML
      title: "x"
      price: 100
      book_parts:
        - slug: chapter-1
          title: Chapter 1
          content: "a"
          unknown_field: "rejected"
    YAML
    error = assert_raises(YamlExporter::UnknownAttributeError) { Book.new.yaml_import(yaml) }
    refute_empty error.message
  end
end
