# frozen_string_literal: true

module YamlExporter
  module Nodes
    # `many :assoc, through: :join, find_by: :column do ... end`.
    #
    # With a block, its attributes (and any positioned_by column) attach to
    # the JOIN row, not the target record. find_by resolves the target
    # globally.
    #
    # With NO block at all the association is a bare reference list: each
    # entry is just the target's find_by value (a string), exactly like
    # ManyReference, but routed through a join model. The join rows are still
    # created/destroyed by the DSL, and positioned_by: — when given — derives
    # the join's position column from the YAML order. An *empty* block is NOT
    # the reference flavor: passing a block (empty or not) opts into the
    # hash-shaped entries, same as the other `many` flavors.
    class ManyThrough < ManyBase
      attr_reader :through

      def initialize(name:, owner_class:, through:, find_by:, positioned_by: nil, &block)
        # Whether a block was passed (even an empty one) decides the YAML
        # shape: block → hash entries, no block → bare reference list.
        @reference_list = block.nil?
        block ||= proc {}

        @through = through.to_sym
        join_reflection = owner_class.reflect_on_association(@through)
        unless join_reflection
          raise ArgumentError,
                "`many #{name.inspect}`: #{owner_class} has no join association `#{through}`"
        end

        super(name: name, owner_class: owner_class, find_by: find_by,
              positioned_by: positioned_by, &block)
      end

      # No block was passed → the YAML is a flat list of find_by values
      # rather than a list of hashes. Mirrors ManyReference, but join rows
      # (and their positioned_by column) are still managed by the DSL.
      def reference_list?
        @reference_list
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
        if reference_list?
          keys = records.map { |join| join.public_send(source_association_name).public_send(@find_by) }
          return [@name.to_s, keys]
        end

        list = records.map do |join|
          target = join.public_send(source_association_name)
          hash = { @find_by.to_s => target.public_send(@find_by) }
          hash.merge!(exporter.build_hash(join, @sub_structure))
          hash
        end
        [@name.to_s, list]
      end

      # Bare reference-list import: entries are find_by values, not hashes.
      # The block-driven flow in ManyBase#import only applies when there are
      # block attributes to write onto the join row.
      def import(parent, data, path:, importer:)
        return super unless reference_list?

        raw = data.key?(@name.to_s) ? data[@name.to_s] : nil
        values = raw.nil? ? [] : raw

        unless values.is_a?(Array)
          raise UnknownAttributeError,
                "#{list_path(path)}: expected a list, got #{values.class}"
        end
        unless values.all? { |v| v.is_a?(String) || v.is_a?(Symbol) || v.is_a?(Numeric) }
          raise UnknownAttributeError,
                "#{list_path(path)}: expected a list of #{@find_by} values, got #{raw.inspect}"
        end

        parent.association(@through).reset
        existing = current_entries(parent)
        kept = Set.new.compare_by_identity

        values.each_with_index do |value, index|
          join = find_or_build_child(parent, { @find_by.to_s => value }, index, existing: existing)
          # positioned_by is DSL-owned: derived from the 1-based array index,
          # mirroring ManyBase#import.
          join.public_send("#{@positioned_by}=", index + 1) if @positioned_by
          join.save!
          kept << join
        end

        destroy_missing(existing, kept)
      end

      def extra_entry_keys
        [@find_by.to_s]
      end

      # find_by is a column on the *target* (e.g. Reviewer.slug), not on the
      # join row — so resolve the type against target_class.
      def extra_entry_schema
        { @find_by => { type: TypeInference.schema_type_for(target_class, @find_by) } }
      end

      # A bare reference list is a flat array of find_by values; the
      # block-driven object-array schema from ManyBase doesn't apply.
      def schema_fragment
        return super unless reference_list?

        item_type = TypeInference.schema_type_for(target_class, @find_by)
        { @name => { type: 'array', items: { type: item_type } } }
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
