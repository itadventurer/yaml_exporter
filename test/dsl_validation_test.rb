# frozen_string_literal: true

require_relative 'test_helper'

module DslValidationRuntimeModels
  class BookPart < ActiveRecord::Base
    self.table_name = 'book_parts'
    belongs_to :book, class_name: 'DslValidationRuntimeModels::Book', optional: true
  end
end

# Declaration-time errors: building `yaml_structure` with an invalid combination of
# arguments must raise before any YAML crosses the boundary.
class DslValidationTest < Minitest::Test
  def setup
    reset_test_database!
  end

  def define_book(&block)
    Class.new(ActiveRecord::Base) do
      self.table_name = 'books'
      include YamlExporter
      yaml_structure(&block)
    end
  end

  # ----- `one` declaration errors ------------------------------------

  def test_one_with_block_and_find_by_raises_at_class_load
    assert_raises(StandardError) do
      define_book do
        attributes :title
        one :book_detail, find_by: :slug do
          attributes :summary
        end
      end
    end
  end

  def test_one_without_block_or_find_by_raises_at_class_load
    assert_raises(StandardError) do
      define_book do
        attributes :title
        one :book_detail
      end
    end
  end

  # ----- `many` declaration errors -----------------------------------

  def test_many_positioned_by_without_block_raises_at_class_load
    assert_raises(StandardError) do
      define_book do
        attributes :title
        many :book_parts, find_by: :slug, positioned_by: :position
      end
    end
  end

  def test_positioned_by_column_also_declared_in_child_attributes_raises_at_class_load
    assert_raises(StandardError) do
      define_book do
        attributes :title
        many :book_parts, positioned_by: :position do
          attributes :title, :content, :position
        end
      end
    end
  end

  # ----- Partner runtime checks --------------------------------------

  def runtime_book_class
    @runtime_book_class ||= begin
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = 'books'
        has_many :book_parts, class_name: 'DslValidationRuntimeModels::BookPart',
                              foreign_key: :book_id, dependent: :destroy
        include YamlExporter
        yaml_structure do
          attributes :title
          many :book_parts, positioned_by: :position do
            attributes :title, :content
          end
        end
      end
      klass
    end
  end

  def test_positioned_column_inside_yaml_entry_raises_on_import
    yaml = <<~YAML
      title: A book
      book_parts:
        - title: Chapter 1
          content: "First"
          position: 1
    YAML
    assert_raises(YamlExporter::UnknownAttributeError) { runtime_book_class.new.yaml_import(yaml) }
  end

  def test_undeclared_key_inside_a_yaml_entry_raises_on_import
    yaml = <<~YAML
      title: A book
      book_parts:
        - title: Chapter 1
          content: "First"
          totally_unknown_key: nope
    YAML
    assert_raises(YamlExporter::UnknownAttributeError) { runtime_book_class.new.yaml_import(yaml) }
  end
end
