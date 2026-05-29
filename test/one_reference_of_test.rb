# frozen_string_literal: true

require_relative 'test_helper'

module OneReferenceOfTestModels
  class User < ActiveRecord::Base
    self.table_name = 'users'
    has_one :corporate_user, class_name: 'OneReferenceOfTestModels::CorporateUser',
                             foreign_key: :user_id
  end

  class CorporateUser < ActiveRecord::Base
    self.table_name = 'corporate_users'
    belongs_to :user, class_name: 'OneReferenceOfTestModels::User'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    belongs_to :responsible_editor,
               class_name: 'OneReferenceOfTestModels::CorporateUser',
               foreign_key: :responsible_editor_id,
               optional: true

    include YamlExporter

    yaml_structure do
      attributes :title
      one :responsible_editor, find_by: :slug, of: :user
    end
  end
end

class OneReferenceOfTest < Minitest::Test
  Book          = OneReferenceOfTestModels::Book
  CorporateUser = OneReferenceOfTestModels::CorporateUser
  User          = OneReferenceOfTestModels::User

  def setup
    reset_test_database!
    @alice_user   = User.create!(name: 'Alice', slug: 'alice')
    @alice_corp   = CorporateUser.create!(name: 'Alice Corp', user_id: @alice_user.id)
  end

  def test_import_resolves_corporate_user_via_user_slug
    book = Book.new
    book.yaml_import(yaml_fixture('one_reference_of', doc: 0))

    reloaded(book) do |book|
      assert_equal @alice_corp.id, book.responsible_editor_id
      assert_equal 'Alice Corp', book.responsible_editor.name
    end
  end

  def test_unresolvable_user_slug_raises_record_not_found
    book = Book.new
    assert_raises(ActiveRecord::RecordNotFound) do
      book.yaml_import(yaml_fixture('one_reference_of', doc: 1))
    end
  end

  def test_user_without_corporate_user_raises_record_not_found
    User.create!(name: 'Orphan', slug: 'orphan-user')
    book = Book.new
    assert_raises(ActiveRecord::RecordNotFound) do
      book.yaml_import(yaml_fixture('one_reference_of', doc: 2))
    end
  end

  def test_null_value_clears_responsible_editor_id
    book = Book.new
    book.yaml_import(yaml_fixture('one_reference_of', doc: 0))
    reloaded(book) { |book| assert_equal @alice_corp.id, book.responsible_editor_id }

    book.yaml_import(yaml_fixture('one_reference_of', doc: 3))

    reloaded(book) do |book|
      assert_nil book.responsible_editor_id
      assert CorporateUser.exists?(@alice_corp.id)
    end
  end

  def test_missing_key_clears_responsible_editor_id
    book = Book.new
    book.yaml_import(yaml_fixture('one_reference_of', doc: 0))
    reloaded(book) { |book| assert_equal @alice_corp.id, book.responsible_editor_id }

    book.yaml_import(yaml_fixture('one_reference_of', doc: 4))

    reloaded(book) { |book| assert_nil book.responsible_editor_id }
  end

  def test_export_emits_user_slug
    book = Book.new
    book.yaml_import(yaml_fixture('one_reference_of', doc: 0))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      assert_equal 'alice', parsed['responsible_editor']
    end
  end

  def test_export_omits_editor_when_absent_by_default
    book = Book.create!(title: 'No Editor')

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      refute parsed.key?('responsible_editor')
    end
  end

  def test_export_emits_null_when_editor_absent_and_omit_nil_disabled
    book = Book.create!(title: 'No Editor')

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export(omit_nil: false))
      assert book.yaml_export(omit_nil: false).include?('responsible_editor')
      assert_nil parsed['responsible_editor']
    end
  end

  def test_round_trip
    book = Book.new
    book.yaml_import(yaml_fixture('one_reference_of', doc: 0))

    exported = reloaded(book) { |book| book.yaml_export }
    other = Book.new
    other.yaml_import(exported)

    reloaded(book) do |book|
      reloaded(other) do |other|
        assert_equal book.responsible_editor_id, other.responsible_editor_id
      end
    end
  end

  def test_dsl_of_without_find_by_raises_at_class_load
    assert_raises(ArgumentError) do
      Class.new(ActiveRecord::Base) do
        self.table_name = 'books'
        include YamlExporter
        yaml_structure do
          attributes :title
          one :responsible_editor, of: :user
        end
      end
    end
  end

  def test_dsl_of_association_not_on_target_raises_at_class_load
    assert_raises(StandardError) do
      Class.new(ActiveRecord::Base) do
        self.table_name = 'books'
        belongs_to :responsible_editor,
                   class_name: 'OneReferenceOfTestModels::CorporateUser',
                   foreign_key: :responsible_editor_id,
                   optional: true
        include YamlExporter
        yaml_structure do
          attributes :title
          one :responsible_editor, find_by: :slug, of: :nonexistent_assoc
        end
      end
    end
  end
end
