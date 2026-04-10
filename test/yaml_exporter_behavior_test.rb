# frozen_string_literal: true

require_relative 'test_helper'

# Contract tests for YamlExporter: import/export, idempotency, nested has_many,
# foreign-key attributes on join rows, has_one, schema validation, and round-trip.
class YamlExporterBehaviorTest < Minitest::Test
  def setup
    HarnessArticleNote.delete_all
    HarnessArticle.delete_all
    HarnessResponse.delete_all
    HarnessAnswer.delete_all
    HarnessQuestion.delete_all
    HarnessQuiz.delete_all
    HarnessTrainingVm.delete_all
    HarnessTraining.delete_all
    HarnessVm.delete_all
  end

  def test_import_yaml_string_creates_nested_records
    quiz = HarnessQuiz.create!(title: 'not my quiz')
    yaml = quiz_yaml_one_question_two_answers(title: 'My quiz')

    quiz.yaml_import(yaml)
    quiz.save!

    quiz_to_check = HarnessQuiz.find(quiz.id)
    assert_equal 'My quiz', quiz_to_check.title
    assert_equal 1, quiz_to_check.harness_questions.count
    q = quiz_to_check.harness_questions.first
    assert_equal 'Q1', q.text
    assert_equal 2, q.harness_answers.count
    assert_equal %w[A B], q.harness_answers.order(:id).pluck(:text)
  end

  def test_import_on_new_unsaved_root_creates_records
    quiz = HarnessQuiz.new
    quiz.yaml_import(quiz_yaml_one_question_two_answers(title: 'From new'))

    quiz.save!
    quiz_to_check = HarnessQuiz.find(quiz.id)
    assert quiz.persisted?
    assert_equal 'From new', quiz_to_check.title
    assert_equal 1, quiz_to_check.harness_questions.count
    assert_equal 2, quiz_to_check.harness_questions.first.harness_answers.count
  end

  def test_reimport_identical_yaml_preserves_ids_and_counts
    quiz = HarnessQuiz.create!(title: 'x')
    yaml = quiz_yaml_one_question_two_answers(title: 'Stable')

    quiz.yaml_import(yaml)
    quiz.save!
    quiz_to_check = HarnessQuiz.find(quiz.id)
    q_id = quiz_to_check.harness_questions.first.id
    a_ids = quiz_to_check.harness_questions.first.harness_answers.order(:id).pluck(:id)

    quiz.yaml_import(yaml)
    quiz.save!
    quiz_to_check = HarnessQuiz.find(quiz.id)

    assert_equal 1, quiz_to_check.harness_questions.count
    assert_equal q_id, quiz_to_check.harness_questions.first.id
    assert_equal a_ids, quiz_to_check.harness_questions.first.harness_answers.order(:id).pluck(:id)
  end

  def test_reimport_updates_root_and_nested_attributes
    quiz = HarnessQuiz.create!(title: 'x')
    quiz.yaml_import(quiz_yaml_one_question_two_answers(title: 'V1', qtext: 'Old Q', answers: [%w[OldA true], %w[OldB false]]))
    quiz.save!

    quizv2 = HarnessQuiz.find(quiz.id)
    quizv2.yaml_import(quiz_yaml_one_question_two_answers(title: 'V2', qtext: 'New Q', answers: [%w[NewA true], %w[NewB false]]))
    quizv2.save!

    quiz_to_check = HarnessQuiz.find(quiz.id)

    assert_equal 'V2', quiz_to_check.title
    q = quiz_to_check.harness_questions.first
    assert_equal 'New Q', q.text
    assert_equal %w[NewA NewB], q.harness_answers.order(:id).pluck(:text)
  end

  def test_training_import_then_changes_join_row_fk_without_reordering
    vm_a = HarnessVm.create!(title: 'VmA')
    vm_b = HarnessVm.create!(title: 'VmB')
    vm_c = HarnessVm.create!(title: 'VmC')
    training = HarnessTraining.create!(name: 'T')

    training.yaml_import(training_yaml(vm_ids: [vm_a.id, vm_b.id]))
    training.save!

    training_to_check = HarnessTraining.find(training.id)
    joins = training_to_check.harness_training_vms.order(:id).to_a
    assert_equal 2, joins.size
    assert_equal vm_a.id, joins[0].harness_vm_id
    assert_equal vm_b.id, joins[1].harness_vm_id
    join_ids = joins.map(&:id)

    training2 = HarnessTraining.find(training.id)
    training2.yaml_import(training_yaml(vm_ids: [vm_c.id, vm_b.id]))
    training2.save!

    training2_to_check = HarnessTraining.find(training.id)

    assert_equal [vm_c.id, vm_b.id],
                 training2_to_check.harness_training_vms.order(:position).pluck(:harness_vm_id),
                 'Join row at each position keeps the same record while FK attrs update'
    assert_equal join_ids.sort, training2_to_check.harness_training_vms.pluck(:id).sort
  end

  def test_training_yaml_with_fewer_join_rows_destroys_removed_joins
    vm_a = HarnessVm.create!(title: 'VmA')
    vm_b = HarnessVm.create!(title: 'VmB')
    training = HarnessTraining.create!(name: 'T')

    training.yaml_import(training_yaml(vm_ids: [vm_a.id, vm_b.id]))
    training.save!

    training_to_check = HarnessTraining.find(training.id)
    assert_equal 2, training_to_check.harness_training_vms.count

    training2 = HarnessTraining.find(training.id)
    training2.yaml_import(training_yaml(vm_ids: [vm_a.id]))
    training2.save!

    training2_to_check = HarnessTraining.find(training.id)

    assert_equal 1, training2_to_check.harness_training_vms.count
    assert_equal vm_a.id, training2_to_check.harness_training_vms.first.harness_vm_id
    assert_equal 2, HarnessVm.count
  end

  def test_yaml_removes_top_level_question_and_dependent_answers
    quiz = HarnessQuiz.create!(title: 'x')
    yaml_two = <<~YAML
      ---
      title: Qz
      harness_questions:
      - text: First
        position: 1
        harness_answers:
        - text: a1
          is_correct: true
      - text: Second
        position: 2
        harness_answers:
        - text: a2
          is_correct: false
    YAML
    quiz.yaml_import(yaml_two)
    quiz.save!

    quiz_to_check = HarnessQuiz.find(quiz.id)
    assert_equal 2, quiz_to_check.harness_questions.count

    yaml_one = <<~YAML
      ---
      title: Qz
      harness_questions:
      - text: First
        position: 1
        harness_answers:
        - text: a1
          is_correct: true
    YAML
    quiz2 = HarnessQuiz.find(quiz.id)
    quiz2.yaml_import(yaml_one)
    quiz2.save!

    quiz2_to_check = HarnessQuiz.find(quiz.id)

    assert_equal 1, quiz2_to_check.harness_questions.count
    assert_equal 'First', quiz2_to_check.harness_questions.first.text
    assert_equal 1, HarnessAnswer.count
  end

  def test_yaml_removes_nested_answer_when_list_shortens
    quiz = HarnessQuiz.create!(title: 'x')
    quiz.yaml_import(quiz_yaml_one_question_two_answers(title: 'Q', answers: [%w[A true], %w[B false]]))
    quiz.save!

    quiz_to_check = HarnessQuiz.find(quiz.id)
    q = quiz_to_check.harness_questions.first
    assert_equal 2, q.harness_answers.count

    quiz2 = HarnessQuiz.find(quiz.id)
    quiz2.yaml_import(quiz_yaml_one_question_two_answers(title: 'Q', answers: [%w[A true]]))
    quiz2.save!

    quiz2_to_check = HarnessQuiz.find(quiz.id)
    q2 = quiz2_to_check.harness_questions.first

    assert_equal 1, q2.harness_answers.count
    assert_equal 'A', q2.harness_answers.first.text
  end

  def test_yaml_adds_question
    quiz = HarnessQuiz.create!(title: 'x')
    quiz.yaml_import(quiz_yaml_one_question_two_answers(title: 'T'))
    quiz.save!

    quiz_to_check = HarnessQuiz.find(quiz.id)
    assert_equal 1, quiz_to_check.harness_questions.count

    yaml_two = <<~YAML
      ---
      title: T
      harness_questions:
      - text: Q1
        position: 1
        harness_answers:
        - text: A
          is_correct: true
      - text: Q2
        position: 2
        harness_answers:
        - text: B
          is_correct: false
    YAML
    quiz2 = HarnessQuiz.find(quiz.id)
    quiz2.yaml_import(yaml_two)
    quiz2.save!

    quiz2_to_check = HarnessQuiz.find(quiz.id)

    assert_equal %w[Q1 Q2], quiz2_to_check.harness_questions.order(:position).pluck(:text)
  end

  def test_yaml_adds_answer_to_existing_question
    quiz = HarnessQuiz.create!(title: 'x')
    quiz.yaml_import(quiz_yaml_one_question_two_answers(title: 'T', answers: [%w[Only true]]))
    quiz.save!

    quiz_to_check = HarnessQuiz.find(quiz.id)
    assert_equal 1, quiz_to_check.harness_questions.first.harness_answers.count

    quiz2 = HarnessQuiz.find(quiz.id)
    quiz2.yaml_import(quiz_yaml_one_question_two_answers(title: 'T'))
    quiz2.save!

    quiz2_to_check = HarnessQuiz.find(quiz.id)

    assert_equal 2, quiz2_to_check.harness_questions.first.harness_answers.count
  end

  def test_yaml_export_then_import_produces_equivalent_tree
    source = HarnessQuiz.create!(title: 'x')
    source.yaml_import(quiz_yaml_one_question_two_answers(title: 'Round', qtext: 'Q', answers: [%w[X true], %w[Y false]]))
    source.save!

    exported = source.yaml_export
    copy = HarnessQuiz.create!(title: 'placeholder')
    copy.yaml_import(exported)
    copy.save!

    assert_equal tree_hash(source), tree_hash(copy)
  end

  def test_yaml_schema_shape_for_harness_quiz
    schema = HarnessQuiz.yaml_schema

    assert_equal 'object', schema[:type]
    assert_kind_of Hash, schema[:properties]
    assert schema[:properties].key?('title')

    questions = schema[:properties]['harness_questions']
    assert_equal 'array', questions[:type]
    assert_equal 'object', questions[:items][:type]
    assert questions[:items][:properties].key?('harness_answers')
    assert_equal 'array', questions[:items][:properties]['harness_answers'][:type]
  end

  def test_invalid_yaml_raises_with_schema_message
    quiz = HarnessQuiz.create!(title: 'x')
    bad = <<~YAML
      ---
      title: []
    YAML

    err = assert_raises(RuntimeError) { quiz.yaml_import(bad) }
    assert_match(/Invalid YAML structure:/, err.message)
  end

  def test_has_one_nested_import_updates_body
    article = HarnessArticle.create!(title: 'A')
    article.yaml_import(<<~YAML)
      ---
      title: A
      harness_article_note:
        body: First
    YAML
    article.save!

    article_to_check = HarnessArticle.find(article.id)
    assert_equal 'First', article.harness_article_note.body

    article2 = HarnessArticle.find(article.id)
    article2.yaml_import(<<~YAML)
      ---
      title: A
      harness_article_note:
        body: Second
    YAML
    article2.save!

    article2_to_check = HarnessArticle.find(article.id)
    assert_equal 'Second', article2_to_check.harness_article_note.body
    assert_equal 1, HarnessArticleNote.count
  end

  def test_omitting_has_one_key_does_not_clear_existing_association
    article = HarnessArticle.create!(title: 'A')
    article.yaml_import(<<~YAML)
      ---
      title: A
      harness_article_note:
        body: Kept
    YAML
    article.save!
    note_id = article.harness_article_note.id

    article2 = HarnessArticle.find(article.id)
    article2.yaml_import(<<~YAML)
      ---
      title: Renamed only
    YAML
    article2.save!

    article2_to_check = HarnessArticle.find(article.id)

    assert_equal 'Renamed only', article2_to_check.title
    assert article2_to_check.harness_article_note
    assert_equal note_id, article2_to_check.harness_article_note.id
    assert_equal 'Kept', article2_to_check.harness_article_note.body
  end

  def test_omitting_optional_belongs_to_fk_attribute_clears_harness_vm_id
    vm = HarnessVm.create!(title: 'Vm')
    article = HarnessArticle.create!(title: 'A')
    article.yaml_import(<<~YAML)
      ---
      title: A
      harness_vm_id: #{vm.id}
      harness_article_note:
        body: N
    YAML
    article.save!

    article_to_check = HarnessArticle.find(article.id)
    assert_equal vm.id, article_to_check.harness_vm_id

    article2 = HarnessArticle.find(article.id)
    article2.yaml_import(<<~YAML)
      ---
      title: A
      harness_article_note:
        body: N
    YAML
    article2.save!
    article2_to_check = HarnessArticle.find(article.id)

    assert_nil article2_to_check.harness_vm_id
  end

  private

  def quiz_yaml_one_question_two_answers(title:, qtext: 'Q1', answers: nil)
    answers ||= [%w[A true], %w[B false]]
    buf = +"---\n"
    buf << "title: #{title}\n"
    buf << "harness_questions:\n"
    buf << "- text: #{qtext}\n"
    buf << "  position: 1\n"
    buf << "  harness_answers:\n"
    answers.each do |text, correct|
      buf << "  - text: #{text}\n"
      buf << "    is_correct: #{correct}\n"
    end
    buf
  end

  def training_yaml(vm_ids:)
    rows = vm_ids.each_with_index.map do |vm_id, i|
      <<~ROW.strip
        - position: #{i}
          harness_vm_id: #{vm_id}
      ROW
    end
    <<~YAML
      ---
      name: T
      harness_training_vms:
      #{rows.join("\n")}
    YAML
  end

  def tree_hash(quiz)
    quiz.save!
    quiz_to_check = HarnessQuiz.find(quiz.id)
    {
      'title' => quiz_to_check.title,
      'harness_questions' => quiz_to_check.harness_questions.order(:id).map do |q|
        {
          'text' => q.text,
          'position' => q.position,
          'harness_answers' => q.harness_answers.order(:id).map do |a|
            { 'text' => a.text, 'is_correct' => a.is_correct }
          end
        }
      end
    }
  end
end
