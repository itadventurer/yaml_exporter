# frozen_string_literal: true

require_relative 'test_helper'

# Regression harness mirroring app-level FileSync / Quiz / TrainingTemplate cases:
# - Quiz -> Question -> Answer: list index merge must not reassign rows when only order changes.
# - Training -> TrainingVm (join): list index merge must keep a stable join row per logical VM.
#
# Expected failures (until fixed): `update_collection` matches nested has_many rows by array
# index only. Reordering YAML updates row 0 with YAML row 0's attributes, etc., so foreign keys
# and "first row by id" no longer line up with semantic order. Match by stable id (or similar)
# in YAML, not by index.
class NestedAssociationRegressionTest < Minitest::Test
  def setup
    HarnessResponse.delete_all
    HarnessAnswer.delete_all
    HarnessQuestion.delete_all
    HarnessQuiz.delete_all
    HarnessTrainingVm.delete_all
    HarnessTraining.delete_all
    HarnessVm.delete_all
  end

  # --- Quiz -> Question -> Answer ---

  def test_lowest_id_answer_row_reflects_first_yaml_answer_block_after_merge
    quiz = HarnessQuiz.create!(title: 'Q')
    q = quiz.harness_questions.create!(text: 'Q1', position: 1)
    q.harness_answers.create!(text: 'Alpha', is_correct: true)
    q.harness_answers.create!(text: 'Beta', is_correct: false)

    yaml = <<~YAML
      ---
      title: Q
      harness_questions:
      - text: Q1
        position: 1
        harness_answers:
        - text: Beta
          is_correct: false
        - text: Alpha
          is_correct: true
    YAML

    quiz.reload.yaml_import(yaml)

    physical_first = HarnessAnswer.where(harness_question_id: q.id).order(:id).first
    # First block in YAML is Beta — index-based merge writes that onto existing_items[0] (lowest id).
    assert_equal 'Beta', physical_first.text,
                 'Lowest-id row should hold the first YAML answer block after in-place merge'
  end

  def test_response_still_references_semantically_same_answer_after_answer_order_change
    quiz = HarnessQuiz.create!(title: 'Q')
    q = quiz.harness_questions.create!(text: 'Q1', position: 1)
    alpha = q.harness_answers.create!(text: 'Alpha', is_correct: true)
    q.harness_answers.create!(text: 'Beta', is_correct: false)

    resp = HarnessResponse.create!(
      harness_quiz: quiz,
      harness_question: q,
      harness_answer: alpha
    )

    yaml = <<~YAML
      ---
      title: Q
      harness_questions:
      - text: Q1
        position: 1
        harness_answers:
        - text: Beta
          is_correct: false
        - text: Alpha
          is_correct: true
    YAML

    quiz.reload.yaml_import(yaml)
    resp.reload

    # Desired behavior: persisted row order (by id) should follow YAML order after stable-key merge.
    q.reload
    assert_equal %w[Beta Alpha],
                 q.harness_answers.order(:id).pluck(:text),
                 'Answer rows ordered by id should match YAML order after stable-key merge'
  end

  # --- Training -> join rows (VM) ---

  def test_join_row_per_vm_stable_when_vm_list_order_changes
    training = HarnessTraining.create!(name: 'T')
    vm_a = HarnessVm.create!(title: 'VmA')
    vm_b = HarnessVm.create!(title: 'VmB')
    j1 = training.harness_training_vms.create!(harness_vm: vm_a, position: 0)
    j2 = training.harness_training_vms.create!(harness_vm: vm_b, position: 1)
    join_id_for_a = j1.id
    join_id_for_b = j2.id

    yaml = <<~YAML
      ---
      name: T
      harness_training_vms:
      - position: 0
        harness_vm_id: #{vm_b.id}
      - position: 1
        harness_vm_id: #{vm_a.id}
    YAML

    training.reload.yaml_import(yaml)
    training.reload

    join_for_a = training.harness_training_vms.find_by!(harness_vm_id: vm_a.id)
    join_for_b = training.harness_training_vms.find_by!(harness_vm_id: vm_b.id)
    by_position = training.harness_training_vms.order(:position)

    assert_equal [vm_b.id, vm_a.id], by_position.pluck(:harness_vm_id),
                 'YAML order should set position 0 to VmB and position 1 to VmA'

    assert_equal join_id_for_a, join_for_a.id,
                 'Join row for VmA must stay the same record when only YAML order changes'
    assert_equal join_id_for_b, join_for_b.id,
                 'Join row for VmB must stay the same record when only YAML order changes'
  end
end
