# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :books, force: true do |t|
    t.string :title, null: false
    t.string :author
    t.decimal :price, precision: 10, scale: 2
    t.references :publisher, foreign_key: true, null: true
    t.string :slug
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
end
