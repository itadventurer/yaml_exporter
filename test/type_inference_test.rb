# frozen_string_literal: true

require_relative 'test_helper'

module TypeInferenceTestModels
  class Author < ActiveRecord::Base
    self.table_name = 'authors'
  end

  class BookDetail < ActiveRecord::Base
    self.table_name = 'book_details'
  end

  class BookReviewer < ActiveRecord::Base
    self.table_name = 'book_reviewers'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
  end
end

class TypeInferenceTest < Minitest::Test
  def setup
    reset_test_database!
  end

  def test_string_column_maps_to_string
    assert_equal 'string',
                 YamlExporter::TypeInference.schema_type_for(TypeInferenceTestModels::Author, :name)
  end

  def test_float_column_maps_to_number
    assert_equal 'number',
                 YamlExporter::TypeInference.schema_type_for(TypeInferenceTestModels::Book, :price)
  end

  def test_integer_column_maps_to_integer
    assert_equal 'integer',
                 YamlExporter::TypeInference.schema_type_for(TypeInferenceTestModels::BookDetail,
                                                             :publication_year)
  end

  def test_text_column_maps_to_string
    assert_equal 'string',
                 YamlExporter::TypeInference.schema_type_for(TypeInferenceTestModels::BookDetail,
                                                             :summary)
  end

  def test_boolean_column_maps_to_boolean
    assert_equal 'boolean',
                 YamlExporter::TypeInference.schema_type_for(TypeInferenceTestModels::BookReviewer,
                                                             :finished)
  end

  def test_column_name_accepts_symbol_or_string
    assert_equal 'string',
                 YamlExporter::TypeInference.schema_type_for(TypeInferenceTestModels::Author, 'name')
    assert_equal 'string',
                 YamlExporter::TypeInference.schema_type_for(TypeInferenceTestModels::Author, :name)
  end

  def test_missing_column_falls_back_to_string
    assert_equal 'string',
                 YamlExporter::TypeInference.schema_type_for(TypeInferenceTestModels::Author,
                                                             :does_not_exist)
  end

  def test_nil_klass_falls_back_to_string
    assert_equal 'string', YamlExporter::TypeInference.schema_type_for(nil, :anything)
  end

  def test_non_ar_klass_falls_back_to_string
    plain = Class.new
    assert_equal 'string', YamlExporter::TypeInference.schema_type_for(plain, :foo)
  end
end
