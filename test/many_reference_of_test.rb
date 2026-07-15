# frozen_string_literal: true

require_relative 'test_helper'

# `many :assoc, find_by: :col, of: :nested` — a standalone reference list
# (here HABTM) whose entries identify targets indirectly through a 1:[0,1]
# association on the target (`of:`). The Book references CorporateUsers, and
# each CorporateUser belongs_to a User with a slug, so the YAML is a flat list
# of user slugs.
module ManyReferenceOfTestModels
  class User < ActiveRecord::Base
    self.table_name = 'users'
  end

  class CorporateUser < ActiveRecord::Base
    self.table_name = 'corporate_users'
    belongs_to :user, class_name: 'ManyReferenceOfTestModels::User'
    # A plural association on the target, used to prove `of:` rejects
    # non-1:[0,1] relations at class load.
    has_many :editor_assignments, class_name: 'ManyReferenceOfTestModels::EditorAssignment',
                                  foreign_key: :corporate_user_id
  end

  class EditorAssignment < ActiveRecord::Base
    self.table_name = 'editor_assignments'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_and_belongs_to_many :corporate_reviewers,
                            class_name: 'ManyReferenceOfTestModels::CorporateUser',
                            join_table: 'books_corporate_users',
                            foreign_key: :book_id,
                            association_foreign_key: :corporate_user_id

    include YamlExporter

    yaml_structure do
      attributes :title
      many :corporate_reviewers, find_by: :slug, of: :user
    end
  end
end

class ManyReferenceOfTest < Minitest::Test
  Book          = ManyReferenceOfTestModels::Book
  CorporateUser = ManyReferenceOfTestModels::CorporateUser
  User          = ManyReferenceOfTestModels::User

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
      corporate_reviewers:
      #{slugs.map { |s| "  - #{s}" }.join("\n")}
    YAML
  end

  def test_import_resolves_user_slugs_to_corporate_users
    book = Book.new
    book.yaml_import(import_yaml(%w[alice bob]))

    reloaded(book) do |book|
      assert_equal [@alice_corp.id, @bob_corp.id].sort,
                   book.corporate_reviewers.pluck(:id).sort
    end
  end

  def test_does_not_auto_create_referenced_records
    assert_equal 2, CorporateUser.count
    Book.new.yaml_import(import_yaml(%w[alice bob]))
    assert_equal 2, CorporateUser.count
    assert_equal 2, User.count
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

  def test_export_emits_sorted_user_slugs
    book = Book.new
    book.yaml_import(import_yaml(%w[bob alice]))

    reloaded(book) do |book|
      parsed = YAML.safe_load(book.yaml_export)
      assert_equal %w[alice bob], parsed['corporate_reviewers']
    end
  end

  def test_reimport_updates_the_set
    book = Book.new
    book.yaml_import(import_yaml(%w[alice bob]))
    reloaded(book) { |book| assert_equal 2, book.corporate_reviewers.count }

    book.yaml_import(import_yaml(%w[alice]))

    reloaded(book) do |book|
      assert_equal [@alice_corp.id], book.corporate_reviewers.pluck(:id)
      assert CorporateUser.exists?(@bob_corp.id)
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
        assert_equal book.corporate_reviewers.pluck(:id).sort,
                     other.corporate_reviewers.pluck(:id).sort
      end
    end
  end

  def test_schema_types_the_list_against_the_user_slug
    schema = Book.yaml_schema
    reviewers = schema[:properties][:corporate_reviewers]
    assert_equal 'array', reviewers[:type]
    assert_equal 'string', reviewers[:items][:type]
  end

  def test_of_pointing_to_nonexistent_association_raises_at_class_load
    assert_raises(ArgumentError) do
      YamlExporter::Nodes::ManyReference.new(
        name: :corporate_reviewers, owner_class: Book, find_by: :slug, of: :nonexistent_assoc
      )
    end
  end

  def test_of_pointing_to_a_has_many_raises_at_class_load
    # CorporateUser#editor_assignments is a has_many — not a 1:[0,1] relation.
    assert_raises(ArgumentError) do
      YamlExporter::Nodes::ManyReference.new(
        name: :corporate_reviewers, owner_class: Book, find_by: :slug, of: :editor_assignments
      )
    end
  end
end
