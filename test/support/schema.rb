# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :quizzes, force: true do |t|
    t.string :title, null: false
    t.string :quiz_type, null: false
  end

  create_table :questions, force: true do |t|
    t.references :quiz, null: false, foreign_key: true
    t.string :text, null: false
    t.string :question_type, null: false
    t.string :feedback
    t.integer :position
  end

  create_table :answers, force: true do |t|
    t.references :question, null: false, foreign_key: true
    t.string :text, null: false
    t.boolean :is_correct, null: false
    t.integer :impact
  end

  create_table :trainings, force: true do |t|
    t.string :name
  end

  create_table :vms, force: true do |t|
    t.string :title
  end

  create_table :training_vms, force: true do |t|
    t.references :training, null: false, foreign_key: true
    t.references :vm, null: false, foreign_key: true
    t.integer :position, default: 0, null: false
  end

  create_table :responses, force: true do |t|
    t.references :quiz, null: false, foreign_key: true
    t.references :question, null: false, foreign_key: true
    t.references :answer, null: false, foreign_key: true
  end

  create_table :articles, force: true do |t|
    t.string :title
    t.references :vm, foreign_key: true, null: true
  end

  create_table :article_notes, force: true do |t|
    t.references :article, null: false, foreign_key: true
    t.string :body
  end
end
