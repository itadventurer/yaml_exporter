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

        of_ref = target_class.reflect_on_association(@of)
        unless of_ref
          raise ArgumentError,
                "`one #{name.inspect}, of: #{of.inspect}`: #{target_class} has no association `#{of}`"
        end

        unless singular_association?(of_ref)
          raise ArgumentError,
                "`one #{name.inspect}, of: #{of.inspect}`: `of:` must be a 1:[0,1] association " \
                "(belongs_to or has_one); got #{of_ref.macro}"
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

      def import(record, data, path:, importer:)
        value = data.key?(@name.to_s) ? data[@name.to_s] : nil

        if value.nil?
          record.public_send("#{@name}=", nil)
          return
        end

        through = through_class.find_by(@find_by => value)
        unless through
          raise ActiveRecord::RecordNotFound,
                "no #{through_class} with #{@find_by}=#{value.inspect}"
        end

        target = find_target_via(through)
        unless target
          raise ActiveRecord::RecordNotFound,
                "no #{target_class} linked to #{through_class} #{@find_by}=#{value.inspect} via `#{@of}`"
        end

        record.public_send("#{@name}=", target)
      end

      def export(record, exporter:)
        target = record.public_send(@name)
        return [@name.to_s, nil] if target.nil?

        through = target.public_send(@of)
        return [@name.to_s, nil] if through.nil?

        [@name.to_s, through.public_send(@find_by)]
      end

      def schema_fragment
        { @name => { type: TypeInference.schema_type_for(through_class, @find_by) } }
      end

      private

      def of_reflection
        @of_reflection ||= target_class.reflect_on_association(@of)
      end

      def through_class
        @through_class ||= of_reflection.klass
      end

      # Navigate from a resolved `through` record back to the target.
      #
      # belongs_to (:user on CorporateUser): FK is on the target.
      #   target_class.find_by(user_id: through.id)
      #
      # has_one (:profile on CorporateUser): FK is on the through record.
      #   target_class.find_by(id: through.corporate_user_id)
      def find_target_via(through)
        if of_reflection.is_a?(ActiveRecord::Reflection::BelongsToReflection)
          pk_val = through.public_send(of_reflection.association_primary_key)
          target_class.find_by(of_reflection.foreign_key => pk_val)
        else # has_one
          fk_val = through.public_send(of_reflection.foreign_key)
          target_class.find_by(of_reflection.association_primary_key => fk_val)
        end
      end

      def singular_association?(reflection)
        reflection.is_a?(ActiveRecord::Reflection::BelongsToReflection) ||
          reflection.is_a?(ActiveRecord::Reflection::HasOneReflection)
      end
    end
  end
end
