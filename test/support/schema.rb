# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :books, force: true do |t|
    t.string :title, null: false
    t.string :author
    t.float :price
    t.references :publisher, foreign_key: true, null: true
    t.string :slug
    # Non-id PK edge-case: the FK to a custom-PK target (Genre, PK :code).
    t.string :primary_genre_code
  end

  create_table :book_parts, force: true do |t|
    t.references :book, null: false, foreign_key: true
    t.string :title
    t.text :content
    t.integer :position
    t.string :slug
  end

  create_table :book_details, force: true do |t|
    t.references :book, null: false, foreign_key: true
    t.text :summary
    t.integer :publication_year
  end

  create_table :authors, force: true do |t|
    t.string :name
    t.string :slug
  end

  create_table :authors_books, force: true, id: false do |t|
    t.references :author, null: false, foreign_key: true
    t.references :book, null: false, foreign_key: true
  end

  create_table :publishers, force: true do |t|
    t.string :name
    t.string :slug
  end

  create_table :reviewers, force: true do |t|
    t.string :name
    t.string :slug
  end

  create_table :book_reviewers, force: true do |t|
    t.references :book, null: false, foreign_key: true
    t.references :reviewer, null: false, foreign_key: true
    t.boolean :finished, default: false
    t.integer :position
  end

  # ---------------------------------------------------------------------
  # Non-id primary key coverage (see test/non_id_pk_test.rb)
  # ---------------------------------------------------------------------
  #
  # Chapter uses its slug as the primary key — exercises the library path
  # where the *child* row has no surrogate id.
  create_table :chapters, primary_key: :slug, id: :string, force: true do |t|
    t.references :book, null: false, foreign_key: true
    t.string :title
    t.text :content
    t.integer :position
  end

  # Genre uses :code as PK and :name as the find_by target — exercises the
  # path where find_by is distinct from the primary key.
  create_table :genres, primary_key: :code, id: :string, force: true do |t|
    t.string :name, null: false
  end

  # HABTM join for Book <-> Genre. Note `genre_code` (not `genre_id`).
  create_table :books_genres, id: false, force: true do |t|
    t.references :book, null: false, foreign_key: true
    t.string :genre_code, null: false
  end

  # has_many :through join for Book <-> Genre. Own id column so the join
  # table itself still has a standard PK while the target does not.
  create_table :genre_assignments, force: true do |t|
    t.references :book, null: false, foreign_key: true
    t.string :genre_code, null: false
    t.integer :position
  end

  # ---------------------------------------------------------------------
  # Multi-association-to-same-class coverage (see test/multi_assoc_test.rb)
  # ---------------------------------------------------------------------
  create_table :people, force: true do |t|
    t.string :name
    t.string :slug
  end

  # Dedicated host table for the OneReference flavor so we don't pile
  # role-specific FK columns onto the already-shared `books` table.
  create_table :annotations, force: true do |t|
    t.string :title
    t.integer :dedicated_to_id
    t.integer :co_dedicatee_id
  end

  # Two HABTM join tables — same target class, distinct roles.
  create_table :book_editors, id: false, force: true do |t|
    t.references :book, null: false, foreign_key: true
    t.references :person, null: false, foreign_key: true
  end

  create_table :book_coauthors, id: false, force: true do |t|
    t.references :book, null: false, foreign_key: true
    t.references :person, null: false, foreign_key: true
  end

  # Two has_many :through join tables — same target class, distinct roles.
  create_table :editorships, force: true do |t|
    t.references :book, null: false, foreign_key: true
    t.references :person, null: false, foreign_key: true
    t.integer :position
  end

  create_table :coauthorships, force: true do |t|
    t.references :book, null: false, foreign_key: true
    t.references :person, null: false, foreign_key: true
    t.integer :position
  end
end
