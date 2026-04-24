# frozen_string_literal: true

module YamlExporter
  module Nodes
    # `many :assoc, through: :join, find_by: :column do ... end`.
    #
    # The block's attributes (and any positioned_by column) attach to the
    # JOIN row, not the target record. find_by resolves the target globally.
    class ManyThrough < ManyBase
      attr_reader :through

      def initialize(name:, owner_class:, through:, find_by:, positioned_by: nil, &block)
        raise ArgumentError, "`many #{name.inspect}`: block required for through:" unless block

        @through = through.to_sym
        join_reflection = owner_class.reflect_on_association(@through)
        unless join_reflection
          raise ArgumentError,
                "`many #{name.inspect}`: #{owner_class} has no join association `#{through}`"
        end

        super(name: name, owner_class: owner_class, find_by: find_by,
              positioned_by: positioned_by, &block)
      end

      def join_class
        @join_class ||= @owner_class.reflect_on_association(@through).klass
      end

      # Block attributes live on the join row.
      def entry_class
        join_class
      end

      # Existing "children" for destroy-missing bookkeeping are the join
      # rows, not the targets: removing a reviewer must drop the join row,
      # never the Reviewer itself. Order follows the through association's
      # default scope (matching is by source-association object, not index,
      # so order doesn't affect correctness here).
      def current_entries(parent)
        parent.association(@through).reset
        parent.public_send(@through).to_a
      end

      def find_or_build_child(parent, entry, _index, existing:)
        key = entry[@find_by.to_s]
        target = target_class.find_by(@find_by => key)
        unless target
          raise ActiveRecord::RecordNotFound,
                "no #{target_class} with #{@find_by}=#{key.inspect}"
        end

        # Match existing join rows by comparing the source association
        # object (AR `==` compares primary keys internally, so this works
        # for surrogate ids and composite PKs alike — no `target.id` needed).
        assoc = source_association_name
        match = existing.find { |join| join.public_send(assoc) == target }
        return match if match

        # `parent.<through>.build` sets the through-side FK for us (respects
        # `association_primary_key`); then we assign the target via its own
        # association setter rather than poking `*_id` columns.
        parent.public_send(@through).build.tap do |join|
          join.public_send("#{assoc}=", target)
        end
      end

      def default_export_order(records)
        records.sort_by do |join|
          target = join.public_send(source_association_name)
          target.public_send(@find_by).to_s
        end
      end

      # The collection the Exporter should walk is the join rows, since
      # block attributes belong to those.
      def export(parent, exporter:)
        records = sort_for_export(Array(parent.public_send(@through)))
        list = records.map do |join|
          target = join.public_send(source_association_name)
          hash = { @find_by.to_s => target.public_send(@find_by) }
          hash.merge!(exporter.build_hash(join, @sub_structure))
          hash
        end
        [@name.to_s, list]
      end

      def extra_entry_keys
        [@find_by.to_s]
      end

      # find_by is a column on the *target* (e.g. Reviewer.slug), not on the
      # join row — so resolve the type against target_class.
      def extra_entry_schema
        { @find_by => { type: TypeInference.schema_type_for(target_class, @find_by) } }
      end

      private

      def source_reflection
        @source_reflection ||= @owner_class.reflect_on_association(@name).source_reflection
      end

      def source_association_name
        source_reflection.name
      end
    end
  end
end
