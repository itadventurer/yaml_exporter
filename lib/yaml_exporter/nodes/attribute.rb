# frozen_string_literal: true

module YamlExporter
  module Nodes
    # A single declared column on the current record.
    #
    # Phase: :pre_save (assigns a value on `record` before `record.save!`).
    class Attribute
      attr_reader :name

      # `owner_class` may be a Class or a 0-arity callable. The callable form
      # matches how the rest of the node tree defers reflection lookups —
      # needed by the anonymous AR classes in dsl_validation_test.
      def initialize(name:, owner_class: nil)
        @name = name.to_sym
        @owner_class_resolver =
          if owner_class.nil?
            nil
          elsif owner_class.respond_to?(:call)
            owner_class
          else
            -> { owner_class }
          end
      end

      def phase
        :pre_save
      end

      def yaml_keys
        [@name.to_s]
      end

      # Missing key, explicit null, and provided value all normalize to the
      # same AR setter call — so "no author" and "author: null" mean the
      # same thing downstream.
      def import(record, data, path:, importer:)
        value = data.key?(@name.to_s) ? data[@name.to_s] : nil
        record.public_send("#{@name}=", value)
      end

      # `text` columns export as YAML literal block scalars (`|`); we signal
      # that by wrapping the string value in LiteralString. `string`/varchar
      # columns stay inline regardless of length.
      def export(record, exporter:)
        value = record.public_send(@name)
        value = LiteralString.new(value) if value.is_a?(::String) && text_column?
        [@name.to_s, value]
      end

      def schema_fragment
        { @name => { type: TypeInference.schema_type_for(owner_class, @name) } }
      end

      private

      def text_column?
        return @text_column if defined?(@text_column)

        @text_column = TypeInference.text_column?(owner_class, @name)
      end

      def owner_class
        return nil unless @owner_class_resolver

        @owner_class ||= @owner_class_resolver.call
      end
    end
  end
end
