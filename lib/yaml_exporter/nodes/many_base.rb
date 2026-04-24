# frozen_string_literal: true

module YamlExporter
  module Nodes
    # Shared base for `many` flavors that take a block:
    # - ManyPositional (no find_by, no through)
    # - ManyFindBy    (find_by, no through)
    # - ManyThrough   (through + find_by)
    #
    # Holds the block's sub-structure and the common accessors. Subclasses
    # override how each YAML entry maps to an existing-or-new child record.
    # ManyReference is NOT a subclass — it has no block and different
    # semantics.
    #
    # Target-class resolution is deferred: we store the owner class and the
    # association name, and resolve the reflected class on demand. Eager
    # resolution breaks anonymous ActiveRecord classes whose inverse
    # associations (often referenced via string `class_name:`) can't be
    # resolved at declaration time.
    class ManyBase
      attr_reader :name, :owner_class, :find_by, :positioned_by, :sub_structure

      def initialize(name:, owner_class:, find_by: nil, positioned_by: nil, &block)
        raise ArgumentError, "`many #{name.inspect}`: block required" unless block

        @name = name.to_sym
        @owner_class = owner_class
        @find_by = find_by&.to_sym
        @positioned_by = positioned_by&.to_sym

        reflection = owner_class.reflect_on_association(@name)
        unless reflection
          raise ArgumentError,
                "`many #{name.inspect}`: #{owner_class} has no association `#{name}`"
        end

        # Pass a lazy class resolver into the inner Builder: attribute-only
        # blocks never trigger it.
        @sub_structure = Builder.new(-> { entry_class }, &block).build

        validate_positioned_by!
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

      # Class against which the block is evaluated. For vanilla `many ... do
      # end` this is the target class. ManyThrough overrides to return the
      # join class (the block's attributes attach to the join row).
      def entry_class
        target_class
      end

      def import(parent, data, path:, importer:)
        entries = data.key?(@name.to_s) ? data[@name.to_s] : nil
        entries = [] if entries.nil?

        unless entries.is_a?(Array)
          raise UnknownAttributeError,
                "#{list_path(path)}: expected a list, got #{entries.class}"
        end

        parent.association(@name).reset
        existing = current_entries(parent)

        # Object-identity set: `find_or_build_child` returns the exact same
        # Ruby object from `existing` when it matches, so we don't have to
        # invent a primary-key-based identifier (keeps this working for
        # composite PKs, custom primary keys, and other non-id models).
        kept = Set.new.compare_by_identity

        entries.each_with_index do |entry, index|
          unless entry.is_a?(Hash)
            raise UnknownAttributeError,
                  "#{entry_path(path, index)}: expected a mapping, got #{entry.class}"
          end

          child = find_or_build_child(parent, entry, index, existing: existing)
          # positioned_by is DSL-owned: the column value is derived from the
          # array index (1-based), never read from the YAML entry. We set it
          # on the child before #apply so the pre-save phase persists it in
          # the same round-trip as the block's attributes.
          child.public_send("#{@positioned_by}=", index + 1) if @positioned_by

          importer.apply(child, @sub_structure, entry,
                         path: entry_path(path, index),
                         extra_keys: extra_entry_keys)
          kept << child
        end

        destroy_missing(existing, kept)
      end

      def export(parent, exporter:)
        records = sort_for_export(Array(parent.public_send(@name)))
        list = records.map { |child| exporter.build_hash(child, @sub_structure) }
        [@name.to_s, list]
      end

      def schema_fragment
        props = @sub_structure.nodes.each_with_object({}) { |n, acc| acc.merge!(n.schema_fragment) }
        extra_entry_schema.each { |k, v| props[k.to_sym] = v }
        { @name => { type: 'array', items: { type: 'object', properties: props } } }
      end

      # --- Subclass hooks --------------------------------------------------

      # Return the child records currently associated with `parent`.
      # Order is whatever the association's default scope produces — if
      # you care (positional semantics), set `-> { order(...) }` on the
      # `has_many`. ManyFindBy / ManyThrough match by column or
      # association object, so order doesn't affect their correctness.
      def current_entries(parent)
        parent.public_send(@name).to_a
      end

      # Build a new child instance bound to `parent`. We delegate to the
      # collection's `.build`, which is the PK-agnostic path: AR fills in the
      # FK (and any polymorphic `*_type` column) by consulting the
      # association's `association_primary_key`, so composite/custom primary
      # keys keep working. Subclasses may override for join-table semantics.
      def build_child(parent)
        parent.public_send(@name).build
      end

      # Destroy children from `existing` that weren't touched this round.
      # `kept` is a `compare_by_identity` Set of Ruby objects; no PK columns
      # are consulted.
      def destroy_missing(existing, kept)
        existing.each do |child|
          child.destroy! unless kept.include?(child)
        end
      end

      # Used by Exporter to produce a stable list order. positioned_by,
      # when present, wins over every other ordering rule. The `to_key`
      # fallback is PK-agnostic (returns `[pk_value]` for surrogate-id rows
      # and the composite array for composite-PK rows); nil (unsaved) folds
      # to [] and leaves Ruby's stable sort to preserve incoming order.
      def sort_for_export(records)
        return records.sort_by { |r| [positioned_value(r), r.to_key || []] } if @positioned_by

        default_export_order(records)
      end

      # Subclasses override to express their "natural" order (find_by for
      # reference-style flavors). Default uses the record's primary key so
      # we don't bake in `:id`.
      def default_export_order(records)
        records.sort_by { |r| r.to_key || [] }
      end

      # Additional entry-level keys the subclass considers legal but that
      # aren't declared in the block (e.g. the `find_by` discriminator).
      def extra_entry_keys
        []
      end

      # Schema fragment for those extra entry keys. Default: infer the type
      # from the `entry_class` (the class the block is evaluated against) —
      # correct for ManyFindBy (entry_class == target_class). ManyThrough
      # overrides because its extra key lives on target_class, not the join.
      # TypeInference gracefully falls back to 'string' for unknown columns.
      def extra_entry_schema
        extra_entry_keys.each_with_object({}) do |k, acc|
          acc[k.to_sym] = { type: TypeInference.schema_type_for(entry_class, k) }
        end
      end

      # Child lookup/construction for a single YAML entry. Must return a
      # record (new or existing) that will be passed through Importer#apply.
      # Abstract here; subclasses must implement.
      def find_or_build_child(_parent, _entry, _index, existing:) # rubocop:disable Lint/UnusedMethodArgument
        raise NotImplementedError, "#{self.class} must implement #find_or_build_child"
      end

      private

      # Nil positions sort last — treat them as the largest possible index so
      # drifted DB rows still land in a deterministic spot when exporting.
      def positioned_value(record)
        value = record.public_send(@positioned_by)
        value.nil? ? Float::INFINITY : value
      end

      def list_path(path)
        path.empty? ? @name.to_s : "#{path}.#{@name}"
      end

      def entry_path(path, index)
        "#{list_path(path)}[#{index}]"
      end

      def validate_positioned_by!
        return if @positioned_by.nil?

        declared = @sub_structure.nodes.grep(Nodes::Attribute).map(&:name)
        return unless declared.include?(@positioned_by)

        raise ArgumentError,
              "`many #{@name.inspect}`: positioned_by column #{@positioned_by.inspect} " \
              "cannot also appear in the block's `attributes` list — the DSL owns it"
      end
    end
  end
end
