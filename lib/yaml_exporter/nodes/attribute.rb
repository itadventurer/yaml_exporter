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

      def export(record, exporter:)
        [@name.to_s, record.public_send(@name)]
      end

      def schema_fragment
        { @name => { type: TypeInference.schema_type_for(owner_class, @name) } }
      end

      private

      def owner_class
        return nil unless @owner_class_resolver

        @owner_class ||= @owner_class_resolver.call
      end
    end
  end
end
