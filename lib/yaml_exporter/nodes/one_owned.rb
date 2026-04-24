# frozen_string_literal: true

module YamlExporter
  module Nodes
    # `one :assoc do ... end` — owned has_one child. The current record owns
    # the child row; missing/null in YAML means "destroy the child".
    #
    # Phase: :post_save (the child carries `parent_id`, so parent must be
    # persisted first).
    class OneOwned
      attr_reader :name, :owner_class, :sub_structure

      def initialize(name:, owner_class:, &block)
        raise ArgumentError, "`one #{name.inspect}`: block required" unless block

        @name = name.to_sym
        @owner_class = owner_class
        reflection = owner_class.reflect_on_association(@name)
        unless reflection
          raise ArgumentError,
                "`one #{name.inspect}`: #{owner_class} has no association `#{name}`"
        end

        @sub_structure = Builder.new(-> { target_class }, &block).build
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
        child_data = data.key?(@name.to_s) ? data[@name.to_s] : nil

        if child_data.nil?
          destroy_existing(record)
          return
        end

        child = find_or_build_child(record)
        importer.apply(child, @sub_structure, child_data, path: child_path(path))
        cache_target(record, child)
      end

      def export(record, exporter:)
        child = record.public_send(@name)
        return [@name.to_s, nil] if child.nil?

        [@name.to_s, exporter.build_hash(child, @sub_structure)]
      end

      def schema_fragment
        { @name => Schema.generate(@sub_structure) }
      end

      private

      def find_or_build_child(parent)
        # Don't trust the in-memory association cache — we may have been
        # re-imported into a parent whose assoc target is stale.
        parent.association(@name).reset
        existing = parent.public_send(@name)
        return existing if existing

        # `build_<assoc>` sets the FK via AR's reflection, which consults
        # `association_primary_key` — PK-agnostic (works for composite /
        # custom primary keys and polymorphic `*_type` columns).
        parent.public_send("build_#{@name}")
      end

      def destroy_existing(parent)
        parent.association(@name).reset
        existing = parent.public_send(@name)
        existing&.destroy!
        cache_target(parent, nil)
      end

      def cache_target(parent, target)
        assoc = parent.association(@name)
        assoc.target = target
        assoc.loaded!
      end

      def child_path(parent_path)
        parent_path.empty? ? @name.to_s : "#{parent_path}.#{@name}"
      end
    end
  end
end
