# frozen_string_literal: true

require_relative 'test_helper'

# How string values are emitted: `text` columns become YAML literal block
# scalars (`|`), `string`/varchar columns stay inline, and two libyaml quirks
# that would silently knock a `text` value out of block style are worked
# around (trailing whitespace, and astral-plane characters such as emoji).
module BlockScalarTestModels
  class BookPart < ActiveRecord::Base
    self.table_name = 'book_parts'
    belongs_to :book, class_name: 'BlockScalarTestModels::Book'
  end

  class Book < ActiveRecord::Base
    self.table_name = 'books'
    has_many :book_parts, class_name: 'BlockScalarTestModels::BookPart',
                          foreign_key: :book_id, dependent: :destroy

    include YamlExporter

    yaml_structure do
      attributes :title
      many :book_parts, find_by: :slug do
        attributes :title, :content, :position
      end
    end
  end
end

class BlockScalarTest < Minitest::Test
  Book = BlockScalarTestModels::Book
  BookPart = BlockScalarTestModels::BookPart

  def setup
    reset_test_database!
  end

  # book_parts.content is a `text` column (block scalar); title is a `string`
  # (stays inline regardless of length).
  def test_export_renders_text_column_as_block_scalar_keeping_varchar_inline
    export_content('Body text here') do |yaml, part|
      assert_includes yaml, 'content: |-'
      assert_equal 'Chapter 1', part['title']
      assert_equal 'Body text here', part['content']
    end
  end

  # A `text` column whose value has trailing whitespace on some lines must
  # still export as a literal block scalar (`|`). Trailing whitespace makes
  # libyaml refuse block style and silently fall back to a double-quoted
  # inline scalar, so we strip it per line to keep the documented invariant
  # ("text columns are always block scalars") holding regardless of value.
  def test_export_strips_trailing_whitespace_to_keep_block_scalar
    messy = "First line with trailing space \n\nSecond line with trailing tab\t\n"
    export_content(messy) do |yaml, part|
      assert_includes yaml, 'content: |', "expected a block scalar, got:\n#{yaml}"
      refute_includes yaml, 'content: "', 'text column fell back to an inline quoted scalar'
      assert_equal "First line with trailing space\n\nSecond line with trailing tab\n",
                   part['content']
    end
  end

  # Astral-plane characters (emoji, codepoint >= U+10000) must not knock a
  # `text` column out of block style. libyaml treats 4-byte UTF-8 as
  # non-printable and would otherwise escape it into an inline double-quoted
  # scalar; we swap such characters through sentinels to keep `|` and emit
  # them literally. BMP characters (umlauts, ✓) were never affected.
  def test_export_keeps_block_scalar_for_text_with_emoji
    content = "Genau! \u{1F4A1} **Tipp**: \u{00FC}ber Schema-Evolution nachdenken. \u{1F600}\n"
    export_content(content) do |yaml, part|
      assert_includes yaml, 'content: |', "emoji forced an inline scalar:\n#{yaml}"
      assert_includes yaml, "\u{1F4A1}", 'emoji was escaped instead of emitted literally'
      refute_includes yaml, '\\U0001F4A1', 'emoji was emitted as an escape sequence'
      assert_equal content, part['content']
    end
  end

  private

  # Exports a single book part carrying `content` and yields the raw YAML
  # string plus the parsed part hash.
  def export_content(content)
    book = Book.create!(title: 'T')
    BookPart.create!(book_id: book.id, slug: 'ch-1', title: 'Chapter 1',
                     content: content, position: 1)

    reloaded(book) do |book|
      yaml = book.yaml_export
      yield yaml, YAML.safe_load(yaml)['book_parts'].first
    end
  end
end
