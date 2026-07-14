# frozen_string_literal: true

module YamlExporter
  module Nodes
    # `one :assoc, find_by: :column` — belongs_to reference. The FK column
    # lives on the current record; the target is externally managed.
    #
    # Phase: :pre_save (sets the FK column on `record` before `record.save!`).
    class OneReference
      attr_reader :name, :owner_class, :find_by

      def initialize(name:, owner_class:, find_by:)
        @name = name.to_sym
        @owner_class = owner_class
        @find_by = find_by.to_sym
        reflection = owner_class.reflect_on_association(@name)
        unless reflection
          raise ArgumentError,
                "`one #{name.inspect}`: #{owner_class} has no association `#{name}`"
        end
      end

      def phase
        :pre_save
      end

      def yaml_keys
        [@name.to_s]
      end

      def target_class
        @target_class ||= @owner_class.reflect_on_association(@name).klass
      end

      # Assign via the association setter (not the raw FK column) so that:
      #   - Rails uses the target's `association_primary_key`, not a hardcoded
      #     :id (composite/custom primary keys keep working).
      #   - The in-memory association cache on `record` is updated, so a
      #     subsequent `record.publisher` returns the freshly-assigned target
      #     instead of a stale one.
      #   - Polymorphic `*_type` columns would be set too, if we ever grow
      #     that feature.
      def import(record, data, path:, importer:)
        value = data.key?(@name.to_s) ? data[@name.to_s] : nil

        if value.nil?
          record.public_send("#{@name}=", nil)
          return
        end

        target = target_class.find_by(@find_by => value)
        unless target
          raise ActiveRecord::RecordNotFound,
                "no #{target_class} with #{@find_by}=#{value.inspect}"
        end

        record.public_send("#{@name}=", target)
      end

      def export(record, exporter:)
        target = record.public_send(@name)
        return [@name.to_s, nil] if target.nil?

        [@name.to_s, target.public_send(@find_by)]
      end

      def schema_fragment
        { @name => { type: TypeInference.schema_type_for(target_class, @find_by) } }
      end
    end
  end
end
