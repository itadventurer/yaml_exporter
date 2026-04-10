# frozen_string_literal: true

class Quiz < ActiveRecord::Base
  include YamlExporter

  has_many :questions, dependent: :destroy
  has_many :responses, dependent: :destroy

  yaml_structure do
    yaml_attribute :title, :quiz_type
    yaml_has_many :questions do
      yaml_attribute :text, :position, :question_type, :feedback
      yaml_has_many :answers do
        yaml_attribute :text, :is_correct, :impact
      end
    end
  end
end

class Question < ActiveRecord::Base
  belongs_to :quiz
  has_many :answers, dependent: :destroy
  has_many :responses, dependent: :destroy
end

class Answer < ActiveRecord::Base
  belongs_to :question
  has_many :responses, dependent: :destroy
end

class Training < ActiveRecord::Base
  include YamlExporter

  has_many :training_vms, dependent: :destroy
  has_many :vms, through: :training_vms

  yaml_structure do
    yaml_attribute :name
    yaml_has_many :training_vms do
      yaml_attribute :position, :vm_id
    end
  end
end

class TrainingVm < ActiveRecord::Base
  belongs_to :training
  belongs_to :vm
end

class Vm < ActiveRecord::Base
  has_many :training_vms, dependent: :destroy
  has_many :trainings, through: :training_vms
end

class Response < ActiveRecord::Base
  belongs_to :quiz
  belongs_to :question
  belongs_to :answer
end

class Article < ActiveRecord::Base
  include YamlExporter

  belongs_to :vm, optional: true
  has_one :article_note, dependent: :destroy

  yaml_structure do
    yaml_attribute :title, :vm_id
    yaml_has_one :article_note do
      yaml_attribute :body
    end
  end
end

class ArticleNote < ActiveRecord::Base
  belongs_to :article
end
