# frozen_string_literal: true

module YamlExporter
  module Nodes
    # `one :assoc, find_by: :col, of: :nested_assoc`
    #
    # Identifies the target record indirectly: the YAML value is looked up on
    # a related model (`of:`) rather than on the target itself.
    #
    # Example: Book `belongs_to :responsible_editor` (CorporateUser), and
    # CorporateUser `belongs_to :user` (User with a slug). Declaring
    #   `one :responsible_editor, find_by: :slug, of: :user`
    # stores the User's slug in the YAML and resolves the CorporateUser on
    # import by reversing the FK.
    #
    # Only 1:[0,1] `of:` associations are permitted (belongs_to or has_one).
    # Phase: :pre_save (sets the FK before record.save!).
    class OneReferenceOf
      include OfResolution

      attr_reader :name, :owner_class, :find_by, :of

      def initialize(name:, owner_class:, find_by:, of:)
        @name = name.to_sym
        @owner_class = owner_class
        @find_by = find_by.to_sym
        @of = of.to_sym

        reflection = owner_class.reflect_on_association(@name)
        unless reflection
          raise ArgumentError,
                "`one #{name.inspect}`: #{owner_class} has no association `#{name}`"
        end

        validate_of_reflection!("one #{name.inspect}")
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

      def import(record, data, path:, importer:)
        value = data.key?(@name.to_s) ? data[@name.to_s] : nil

        if value.nil?
          record.public_send("#{@name}=", nil)
          return
        end

        related = of_class.find_by(@find_by => value)
        unless related
          raise ActiveRecord::RecordNotFound,
                "no #{of_class} with #{@find_by}=#{value.inspect}"
        end

        target = find_target_via(related)
        unless target
          raise ActiveRecord::RecordNotFound,
                "no #{target_class} linked to #{of_class} #{@find_by}=#{value.inspect} via `#{@of}`"
        end

        record.public_send("#{@name}=", target)
      end

      def export(record, exporter:)
        target = record.public_send(@name)
        return [@name.to_s, nil] if target.nil?

        [@name.to_s, of_value_for(target)]
      end

      def schema_fragment
        { @name => { type: TypeInference.schema_type_for(of_class, @find_by) } }
      end
    end
  end
end
