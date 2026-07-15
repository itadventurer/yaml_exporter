# frozen_string_literal: true

module YamlExporter
  module Nodes
    # `many :assoc, find_by: :column` — standalone reference list (HABTM or
    # has_many). No block, no entry attributes: each YAML string resolves to
    # an existing target record via `find_by`. Target records are never
    # created or mutated; only the association is updated.
    #
    # With `of:` the value is resolved indirectly through a 1:[0,1]
    # association on the target (see OfResolution), so the YAML lists the
    # find_by value of a *related* model (e.g. the user slug behind each
    # target) rather than a column on the target itself.
    #
    # Phase: :post_save (join rows / FK need parent.id).
    class ManyReference
      include OfResolution

      attr_reader :name, :owner_class, :find_by, :of

      def initialize(name:, owner_class:, find_by:, of: nil)
        @name = name.to_sym
        @owner_class = owner_class
        @find_by = find_by.to_sym
        @of = of&.to_sym
        reflection = owner_class.reflect_on_association(@name)
        unless reflection
          raise ArgumentError,
                "`many #{name.inspect}`: #{owner_class} has no association `#{name}`"
        end

        validate_of_reflection!("many #{name.inspect}") if @of
      end

      def phase
        :post_save
      end

      def yaml_keys
        [@name.to_s]
      end

      def target_class
        @target_class ||= @owner_class.reflect_on_association(@name).klass
      end

      def import(record, data, path:, importer:)
        raw = data.key?(@name.to_s) ? data[@name.to_s] : nil
        values = Array(raw)

        unless values.all? { |v| v.is_a?(String) || v.is_a?(Symbol) || v.is_a?(Numeric) }
          raise UnknownAttributeError,
                "#{describe_path(path)}: expected a list of #{@find_by} values, got #{raw.inspect}"
        end

        targets = values.map do |value|
          resolve_target(value) ||
            (raise ActiveRecord::RecordNotFound, not_found_message(value))
        end

        record.public_send("#{@name}=", targets)
      end

      def export(record, exporter:)
        targets = Array(record.public_send(@name))
        keys = targets.map { |t| key_for(t) }.compact.sort
        [@name.to_s, keys]
      end

      def schema_fragment
        key_class = @of ? of_class : target_class
        item_type = TypeInference.schema_type_for(key_class, @find_by)
        { @name => { type: 'array', items: { type: item_type } } }
      end

      private

      def resolve_target(value)
        @of ? resolve_target_by_of(value) : target_class.find_by(@find_by => value)
      end

      def key_for(target)
        @of ? of_value_for(target) : target.public_send(@find_by)
      end

      def not_found_message(value)
        if @of
          "no #{target_class} for #{of_class} with #{@find_by}=#{value.inspect} via `#{@of}`"
        else
          "no #{target_class} with #{@find_by}=#{value.inspect}"
        end
      end

      def describe_path(path)
        path.empty? ? @name.to_s : "#{path}.#{@name}"
      end
    end
  end
end
