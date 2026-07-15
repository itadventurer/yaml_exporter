# frozen_string_literal: true

module YamlExporter
  module Nodes
    # Shared `of:` navigation for reference nodes that identify their target
    # indirectly: the YAML value names a column on a *related* model
    # (`of:`) reachable from the target, not on the target itself.
    #
    # Example: a reviewer target is a CorporateUser, and
    # CorporateUser `belongs_to :user` (a User with a slug). Declaring
    # `find_by: :slug, of: :user` stores the User's slug in the YAML and, on
    # import, resolves the User first and then reverses `of:` back to the
    # CorporateUser.
    #
    # Mixed into OneReferenceOf, ManyReference and ManyThrough. The host must
    # provide `target_class` and set `@find_by` and `@of` (both symbols).
    module OfResolution
      # The related model that actually carries the find_by column
      # (CorporateUser.user -> User).
      def of_reflection
        @of_reflection ||= target_class.reflect_on_association(@of)
      end

      # The class of the related model (CorporateUser.user -> User).
      def of_class
        @of_class ||= of_reflection.klass
      end

      # Resolve a single YAML value to a target record: find the related
      # record by find_by, then reverse `of:` back to the target. Returns nil
      # if either lookup misses.
      def resolve_target_by_of(value)
        related = of_class.find_by(@find_by => value)
        return nil unless related

        find_target_via(related)
      end

      # Navigate from a resolved related record back to the target.
      #
      # belongs_to (:user on CorporateUser): FK is on the target.
      #   target_class.find_by(user_id: related.id)
      # has_one (:profile on CorporateUser): FK is on the related record.
      #   target_class.find_by(id: related.corporate_user_id)
      def find_target_via(related)
        if of_reflection.is_a?(ActiveRecord::Reflection::BelongsToReflection)
          pk_val = related.public_send(of_reflection.association_primary_key)
          target_class.find_by(of_reflection.foreign_key => pk_val)
        else # has_one
          fk_val = related.public_send(of_reflection.foreign_key)
          target_class.find_by(of_reflection.association_primary_key => fk_val)
        end
      end

      # The YAML value for a target: the find_by column on its `of:` relation.
      # nil when the target has no related record (can't be represented).
      def of_value_for(target)
        related = target.public_send(@of)
        related&.public_send(@find_by)
      end

      # Declaration-time check: `of:` must name a 1:[0,1] association on the
      # target. Raises ArgumentError at class load otherwise.
      def validate_of_reflection!(node_label)
        of_ref = target_class.reflect_on_association(@of)
        unless of_ref
          raise ArgumentError,
                "`#{node_label}, of: #{@of.inspect}`: #{target_class} has no association `#{@of}`"
        end

        return if singular_of_association?(of_ref)

        raise ArgumentError,
              "`#{node_label}, of: #{@of.inspect}`: `of:` must be a 1:[0,1] association " \
              "(belongs_to or has_one); got #{of_ref.macro}"
      end

      def singular_of_association?(reflection)
        reflection.is_a?(ActiveRecord::Reflection::BelongsToReflection) ||
          reflection.is_a?(ActiveRecord::Reflection::HasOneReflection)
      end
    end
  end
end
