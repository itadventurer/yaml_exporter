# frozen_string_literal: true

require 'bundler/setup'
require 'active_record'
require 'yaml_exporter'
require 'minitest/autorun'
require 'minitest/pride'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

ActiveRecord::Schema.define do
  create_table :harness_quizzes, force: true do |t|
    t.string :title
  end

  create_table :harness_questions, force: true do |t|
    t.references :harness_quiz, null: false, foreign_key: true
    t.string :text
    t.integer :position
  end

  create_table :harness_answers, force: true do |t|
    t.references :harness_question, null: false, foreign_key: true
    t.string :text
    t.boolean :is_correct, default: false, null: false
  end

  create_table :harness_trainings, force: true do |t|
    t.string :name
  end

  create_table :harness_vms, force: true do |t|
    t.string :title
  end

  create_table :harness_training_vms, force: true do |t|
    t.references :harness_training, null: false, foreign_key: true
    t.references :harness_vm, null: false, foreign_key: true
    t.integer :position, default: 0, null: false
  end

  create_table :harness_responses, force: true do |t|
    t.references :harness_quiz, null: false, foreign_key: true
    t.references :harness_question, null: false, foreign_key: true
    t.references :harness_answer, null: false, foreign_key: true
  end
end

class HarnessQuiz < ActiveRecord::Base
  include YamlExporter

  has_many :harness_questions, dependent: :destroy
  has_many :harness_responses, dependent: :destroy

  yaml_structure do
    yaml_attribute :title
    yaml_has_many :harness_questions do
      yaml_attribute :text, :position
      yaml_has_many :harness_answers do
        yaml_attribute :text, :is_correct
      end
    end
  end
end

class HarnessQuestion < ActiveRecord::Base
  belongs_to :harness_quiz
  has_many :harness_answers, dependent: :destroy
  has_many :harness_responses, dependent: :destroy
end

class HarnessAnswer < ActiveRecord::Base
  belongs_to :harness_question
  has_many :harness_responses, dependent: :destroy
end

class HarnessTraining < ActiveRecord::Base
  include YamlExporter

  has_many :harness_training_vms, dependent: :destroy
  has_many :harness_vms, through: :harness_training_vms

  yaml_structure do
    yaml_attribute :name
    yaml_has_many :harness_training_vms do
      yaml_attribute :position, :harness_vm_id
    end
  end
end

class HarnessTrainingVm < ActiveRecord::Base
  belongs_to :harness_training
  belongs_to :harness_vm
end

class HarnessVm < ActiveRecord::Base
  has_many :harness_training_vms, dependent: :destroy
  has_many :harness_trainings, through: :harness_training_vms
end

class HarnessResponse < ActiveRecord::Base
  belongs_to :harness_quiz
  belongs_to :harness_question
  belongs_to :harness_answer
end
