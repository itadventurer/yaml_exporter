# frozen_string_literal: true

require_relative 'test_helper'

# `many :assoc, through: :join, find_by: :col, of: :nested` — a bare reference
# list routed through a join model, where each YAML value identifies the
# target *indirectly*: it is a column on a 1:[0,1] association of the target
# (`of:`), not on the target itself.
#
# Here a Book references CorporateUsers through editor_assignments, and each
# CorporateUser belongs_to a User carrying the slug. So the YAML is a flat
# list of user slugs.
module ManyThroughOfTestModels
  class User < ActiveRecord::Base
    self.table_name = 'users'
  end

  class CorporateUser < ActiveRecord::Base
    self.table_name = 'corporate_users'
    belongs_to :user, class_name: 'ManyThroughOfTestModels::User'
  end

  class EditorAssignment < ActiveRecord::Base
    self.table_name = 'editor_assignments'
    belongs_to :book, class_name: 'ManyThroughOfTestModels::Book'
    belongs_to :corporate_user, class_name: 'ManyThroughOfTestModels::CorporateUser'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_many :editor_assignments, class_name: 'ManyThroughOfTestModels::EditorAssignment',
                                  foreign_key: :book_id, dependent: :destroy
    has_many :editorial_editors, through: :editor_assignments,
                                 source: :corporate_user,
                                 class_name: 'ManyThroughOfTestModels::CorporateUser'

    include YamlExporter

    yaml_structure do
      attributes :title
      many :editorial_editors, through: :editor_assignments,
                               find_by: :slug, of: :user, positioned_by: :position
    end
  end
end

class ManyThroughOfTest < Minitest::Test
  Book          = ManyThroughOfTestModels::Book
  CorporateUser = ManyThroughOfTestModels::CorporateUser
  User          = ManyThroughOfTestModels::User
  EditorAssignment = ManyThroughOfTestModels::EditorAssignment

  def setup
    reset_test_database!
    @alice_user = User.create!(name: 'Alice', slug: 'alice')
    @bob_user   = User.create!(name: 'Bob',   slug: 'bob')
    @alice_corp = CorporateUser.create!(name: 'Alice Corp', user_id: @alice_user.id)
    @bob_corp   = CorporateUser.create!(name: 'Bob Corp',   user_id: @bob_user.id)
  end

  def import_yaml(slugs)
    <<~YAML
      title: Ruby on Rails Tutorial
      editorial_editors:
      #{slugs.map { |s| "  - #{s}" }.join("\n")}
    YAML
  end

  def test_import_resolves_user_slugs_to_corporate_users_via_join
    book = Book.new
    book.yaml_import(import_yaml(%w[alice bob]))

    reloaded(book) do |book|
      assert_equal [@alice_corp.id, @bob_corp.id].sort,
                   book.editorial_editors.pluck(:id).sort
      assert_equal 2, book.editor_assignments.count
    end
  end

  def test_does_not_touch_users_or_corporate_users
    assert_equal 2, User.count
    assert_equal 2, CorporateUser.count
    Book.new.yaml_import(import_yaml(%w[alice bob]))
    assert_equal 2, User.count
    assert_equal 2, CorporateUser.count
  end

  def test_position_is_derived_from_yaml_order
    book = Book.new
    book.yaml_import(import_yaml(%w[bob alice]))

    reloaded(book) do |book|
      positions = book.editor_assignments.includes(:corporate_user).each_with_object({}) do |ea, h|
        h[ea.corporate_user.user.slug] = ea.position
      end
      assert_equal({ 'bob' => 1, 'alice' => 2 }, positions)
    end
  end

  def test_unknown_user_slug_raises_record_not_found
    book = Book.new
    assert_raises(ActiveRecord::RecordNotFound) do
      book.yaml_import(import_yaml(%w[nobody]))
    end
  end

  def test_user_without_corporate_user_raises_record_not_found
    User.create!(name: 'Orphan', slug: 'orphan-user')
    book = Book.new
    assert_raises(ActiveRecord::RecordNotFound) do
      book.yaml_import(import_yaml(%w[orphan-user]))
    end
  end

  def test_export_emits_user_slugs_ordered_by_position
    book = Book.new
    book.yaml_import(import_yaml(%w[bob alice]))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      assert_equal %w[bob alice], parsed['editorial_editors']
    end
  end

  def test_removal_only_drops_join_rows
    book = Book.new
    book.yaml_import(import_yaml(%w[alice bob]))
    reloaded(book) { |book| assert_equal 2, book.editor_assignments.count }

    book.yaml_import(import_yaml(%w[alice]))

    reloaded(book) do |book|
      assert_equal [@alice_corp.id], book.editorial_editors.pluck(:id)
      assert_equal 1, book.editor_assignments.count
      assert CorporateUser.exists?(@bob_corp.id)
      assert User.exists?(@bob_user.id)
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
        assert_equal book.editorial_editors.pluck(:id).sort,
                     other.editorial_editors.pluck(:id).sort
      end
    end
  end

  def test_schema_types_the_list_against_the_user_slug
    schema = Book.yaml_schema
    editors = schema[:properties][:editorial_editors]
    assert_equal 'array', editors[:type]
    assert_equal 'string', editors[:items][:type]
  end
end
