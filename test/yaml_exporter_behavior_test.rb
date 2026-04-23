# frozen_string_literal: true

require_relative 'test_helper'

# Contract tests for YamlExporter: import/export, idempotency, nested has_many,
# foreign-key attributes on join rows, has_one, schema validation, and round-trip.
# Quiz / training / article payloads live in multi-document files under test/fixtures/yaml/.
class YamlExporterBehaviorTest < Minitest::Test
  def setup
    reset_test_database!
  end

  def test_import_yaml_string_creates_nested_records
    quiz = Quiz.create!(title: 'not my quiz', quiz_type: 'multiple_choice')

    quiz.yaml_import(yaml_fixture('quiz', doc: 0))
    quiz.save!

    quiz_to_check = Quiz.find(quiz.id)
    assert_equal 'One question, two answers', quiz_to_check.title
    assert_equal 1, quiz_to_check.questions.count
    q = quiz_to_check.questions.first
    assert_equal 'First', q.text
    assert_equal 2, q.answers.count
    assert_equal %w[A B], q.answers.order(:id).pluck(:text)
  end

  def test_import_on_new_unsaved_root_creates_records
    quiz = Quiz.new
    quiz.yaml_import(yaml_fixture('quiz', doc: 0))

    quiz.save!
    quiz_to_check = Quiz.find(quiz.id)
    assert quiz.persisted?
    assert_equal 'One question, two answers', quiz_to_check.title
    assert_equal 1, quiz_to_check.questions.count
    assert_equal 2, quiz_to_check.questions.first.answers.count
  end

  def test_reimport_identical_yaml_preserves_ids_and_counts
    quiz = Quiz.create!(title: 'x', quiz_type: 'multiple_choice')
    yaml = yaml_fixture('quiz', doc: 0)

    quiz.yaml_import(yaml)
    quiz.save!
    quiz_to_check = Quiz.find(quiz.id)
    q_id = quiz_to_check.questions.first.id
    a_ids = quiz_to_check.questions.first.answers.order(:id).pluck(:id)

    quiz.yaml_import(yaml)
    quiz.save!
    quiz_to_check = Quiz.find(quiz.id)

    assert_equal 1, quiz_to_check.questions.count
    assert_equal q_id, quiz_to_check.questions.first.id
    assert_equal a_ids, quiz_to_check.questions.first.answers.order(:id).pluck(:id)
  end

  def test_reimport_updates_root_and_nested_attributes
    quiz = Quiz.create!(title: 'x', quiz_type: 'multiple_choice')
    quiz.yaml_import(yaml_fixture('quiz', doc: 0))
    quiz.save!

    quizv2 = Quiz.find(quiz.id)
    quizv2.yaml_import(yaml_fixture('quiz', doc: 2))
    quizv2.save!

    quiz_to_check = Quiz.find(quiz.id)

    assert_equal 'One question, two answers, renamed everything', quiz_to_check.title
    q = quiz_to_check.questions.first
    assert_equal 'New Q', q.text
    assert_equal %w[NewA NewB], q.answers.order(:id).pluck(:text)
  end

  def test_foreign_key_attribute_on_join_row_changed
    Vm.create!(id: 1, title: 'VmA')
    Vm.create!(id: 2, title: 'VmB')
    Vm.create!(id: 3, title: 'VmC')
    training = Training.create!(name: 'T')

    training.yaml_import(yaml_fixture('training', doc: 0))
    training.save!

    training_to_check = Training.find(training.id)
    joins = training_to_check.training_vms.order(:id).to_a
    assert_equal 2, joins.size
    join_ids = joins.map(&:id)
    assert_equal [1, 2], join_ids

    training2 = Training.find(training.id)
    training2.yaml_import(yaml_fixture('training', doc: 1))
    training2.save!

    training2_to_check = Training.find(training.id)

    assert_equal [3, 2],
                 training2_to_check.training_vms.order(:position).pluck(:vm_id),
                 'Join row at each position keeps the same record while FK attrs update'
    assert_equal join_ids.sort, training2_to_check.training_vms.pluck(:id).sort
  end

  def test_foreign_key_attribute_on_join_row_removed
    Vm.create!(id: 1, title: 'VmA')
    Vm.create!(id: 2, title: 'VmB')
    training = Training.create!(name: 'T')

    training.yaml_import(yaml_fixture('training', doc: 0))
    training.save!

    training_to_check = Training.find(training.id)
    assert_equal 2, training_to_check.training_vms.count

    training2 = Training.find(training.id)
    training2.yaml_import(yaml_fixture('training', doc: 2))
    training2.save!

    training2_to_check = Training.find(training.id)

    assert_equal 1, training2_to_check.training_vms.count
    assert_equal 1, training2_to_check.training_vms.first.vm_id
  end

  def test_yaml_removes_top_level_question_and_dependent_answers
    quiz = Quiz.create!(title: 'x', quiz_type: 'multiple_choice')

    quiz.yaml_import(yaml_fixture('quiz', doc: 3))
    quiz.save!

    quiz_to_check = Quiz.find(quiz.id)
    assert_equal 2, quiz_to_check.questions.count
    assert_equal 3, quiz_to_check.questions.first.answers.count
    assert_equal 1, quiz_to_check.questions.second.answers.count

    quiz2 = Quiz.find(quiz.id)
    # Doc 0 matches the first question of doc 3 but drops the second question and the extra answer on First.
    quiz2.yaml_import(yaml_fixture('quiz', doc: 0))
    quiz2.save!

    quiz2_to_check = Quiz.find(quiz.id)

    assert_equal 1, quiz2_to_check.questions.count
    assert_equal 'First', quiz2_to_check.questions.first.text
    assert_equal 2, Answer.count
  end

  def test_inner_join_row_removed
    quiz = Quiz.create!(title: 'x', quiz_type: 'multiple_choice')
    quiz.yaml_import(yaml_fixture('quiz', doc: 0))
    quiz.save!

    quiz_to_check = Quiz.find(quiz.id)
    q = quiz_to_check.questions.first
    assert_equal 2, q.answers.count

    quiz2 = Quiz.find(quiz.id)
    quiz2.yaml_import(yaml_fixture('quiz', doc: 4))
    quiz2.save!

    quiz2_to_check = Quiz.find(quiz.id)
    q2 = quiz2_to_check.questions.first

    assert_equal 1, q2.answers.count
    assert_equal 'A', q2.answers.first.text
  end

  def test_yaml_adds_question_and_answer
    quiz = Quiz.create!(title: 'x', quiz_type: 'multiple_choice')
    quiz.yaml_import(yaml_fixture('quiz', doc: 0))
    quiz.save!

    quiz_to_check = Quiz.find(quiz.id)
    assert_equal 1, quiz_to_check.questions.count

    quiz2 = Quiz.find(quiz.id)
    quiz2.yaml_import(yaml_fixture('quiz', doc: 3))
    quiz2.save!

    quiz2_to_check = Quiz.find(quiz.id)

    assert_equal %w[First Second], quiz2_to_check.questions.order(:position).pluck(:text)
    assert_equal %w[A B C], quiz2_to_check.questions.first.answers.order(:id).pluck(:text)
  end


  def test_yaml_export_then_import_produces_equivalent_tree
    source = Quiz.create!(title: 'x', quiz_type: 'multiple_choice')
    source.yaml_import(yaml_fixture('quiz', doc: 0))
    source.save!

    exported = source.yaml_export
    copy = Quiz.create!(title: 'placeholder', quiz_type: 'placeholder')
    copy.yaml_import(exported)
    copy.save!

    assert_equal parsed_yaml_tree(source), parsed_yaml_tree(copy)
  end

  def test_yaml_schema_shape_for_quiz
    schema = Quiz.yaml_schema

    assert_equal 'object', schema[:type]
    assert_kind_of Hash, schema[:properties]
    assert schema[:properties].key?('title')
    assert schema[:properties].key?('quiz_type')

    questions = schema[:properties]['questions']
    assert_equal 'array', questions[:type]
    assert_equal 'object', questions[:items][:type]
    assert questions[:items][:properties].key?('answers')
    assert_equal 'array', questions[:items][:properties]['answers'][:type]
  end

  def test_invalid_yaml_raises_with_schema_message
    quiz = Quiz.create!(title: 'x', quiz_type: 'multiple_choice')

    err = assert_raises(RuntimeError) { quiz.yaml_import(yaml_fixture('quiz', doc: 8)) }
    assert_match(/Invalid YAML structure:/, err.message)
  end

  def test_has_one_nested_import_updates_body
    article = Article.create!(title: 'A')
    article.yaml_import(yaml_fixture('article', doc: 0))
    article.save!

    article_to_check = Article.find(article.id)
    assert_equal 'First', article.article_note.body

    article2 = Article.find(article.id)
    article2.yaml_import(yaml_fixture('article', doc: 1))
    article2.save!

    article2_to_check = Article.find(article.id)
    assert_equal 'Second', article2_to_check.article_note.body
    assert_equal 1, ArticleNote.count
  end

  def test_omitting_has_one_key_does_not_clear_existing_association
    article = Article.create!(title: 'A')
    article.yaml_import(yaml_fixture('article', doc: 2))
    article.save!
    note_id = article.article_note.id

    article2 = Article.find(article.id)
    article2.yaml_import(yaml_fixture('article', doc: 3))
    article2.save!

    article2_to_check = Article.find(article.id)

    assert_equal 'Renamed only', article2_to_check.title
    assert article2_to_check.article_note
    assert_equal note_id, article2_to_check.article_note.id
    assert_equal 'Kept', article2_to_check.article_note.body
  end

  def test_omitting_optional_belongs_to_fk_attribute_clears_vm_id
    Vm.create!(id: 1, title: 'Vm')
    article = Article.create!(title: 'A')
    article.yaml_import(yaml_fixture('article', doc: 4))
    article.save!

    article_to_check = Article.find(article.id)
    assert_equal 1, article_to_check.vm_id

    article2 = Article.find(article.id)
    article2.yaml_import(yaml_fixture('article', doc: 5))
    article2.save!
    article2_to_check = Article.find(article.id)

    assert_nil article2_to_check.vm_id
  end

  private

  def parsed_yaml_tree(quiz)
    YAML.safe_load(quiz.reload.yaml_export, permitted_classes: [], permitted_symbols: [], aliases: true)
  end
end
