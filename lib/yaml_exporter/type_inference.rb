# frozen_string_literal: true

module YamlExporter
  # Maps an ActiveRecord column type to a JSON-schema primitive.
  #
  # Single source of truth used by every node that emits a `type:` entry
  # in the generated schema (Nodes::Attribute, Nodes::OneReference,
  # Nodes::ManyReference, and the extra_entry_keys path in Nodes::ManyBase).
  #
  # Unknown or un-resolvable columns fall back to 'string' so the schema
  # always validates as JSON-schema-ish.
  module TypeInference
    # AR column type -> JSON-schema primitive. Date/time stay 'string' on
    # purpose: YAML round-trips them as ISO-8601 strings by default, and we
    # don't (yet) emit a `format:` facet.
    COLUMN_TYPE_TO_JSON_SCHEMA = {
      string:    'string',
      text:      'string',
      uuid:      'string',
      binary:    'string',
      integer:   'integer',
      bigint:    'integer',
      float:     'number',
      decimal:   'number',
      boolean:   'boolean',
      date:      'string',
      datetime:  'string',
      time:      'string',
      timestamp: 'string',
      json:      'object',
      jsonb:     'object'
    }.freeze

    FALLBACK = 'string'

    # Returns the JSON-schema type string for `column_name` on `klass`.
    # `klass` may be nil (e.g. declaration-time lookup on an anonymous
    # class whose table doesn't exist yet) — we quietly fall back.
    def self.schema_type_for(klass, column_name)
      return FALLBACK unless klass.respond_to?(:columns_hash)

      column = klass.columns_hash[column_name.to_s]
      return FALLBACK unless column

      COLUMN_TYPE_TO_JSON_SCHEMA[column.type] || FALLBACK
    rescue ActiveRecord::ActiveRecordError
      FALLBACK
    end

    # True when `column_name` on `klass` is a `text` column (as opposed to a
    # `string`/varchar). Drives whether string values export as YAML literal
    # block scalars. Unknown/unresolvable columns are treated as non-text.
    def self.text_column?(klass, column_name)
      return false unless klass.respond_to?(:columns_hash)

      column = klass.columns_hash[column_name.to_s]
      return false unless column

      column.type == :text
    rescue ActiveRecord::ActiveRecordError
      false
    end
  end
end
