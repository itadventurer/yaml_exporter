# frozen_string_literal: true

module YamlExporter
  module Nodes
    # `many :assoc, find_by: :column do ... end` — identity is the find_by
    # column value. Existing rows are matched by key; duplicates in the
    # incoming YAML raise DuplicateKeyError.
    class ManyFindBy < ManyBase
      def find_or_build_child(parent, entry, _index, existing:)
        key = entry[@find_by.to_s]
        match = existing.find { |c| c.public_send(@find_by) == key }
        return match if match

        build_child(parent).tap do |child|
          child.public_send("#{@find_by}=", key)
        end
      end

      def default_export_order(records)
        records.sort_by { |r| r.public_send(@find_by).to_s }
      end

      def extra_entry_keys
        [@find_by.to_s]
      end

      # `extra_entry_schema` is inherited from ManyBase — entry_class here is
      # the target class, which is exactly where @find_by lives, so the
      # default TypeInference lookup produces the right type.

      # Re-emit the find_by column first in each entry so round-trips stay
      # stable (and readers see the discriminator up top).
      def export(parent, exporter:)
        records = sort_for_export(Array(parent.public_send(@name)))
        list = records.map do |child|
          hash = { @find_by.to_s => child.public_send(@find_by) }
          hash.merge!(exporter.build_hash(child, @sub_structure))
          hash
        end
        [@name.to_s, list]
      end

      private

      # Guarantees duplicates-in-YAML fail loudly instead of silently
      # overwriting each other by index.
      def reject_duplicates!(entries, path)
        seen = {}
        entries.each_with_index do |entry, index|
          key = entry[@find_by.to_s]
          if seen.key?(key)
            raise DuplicateKeyError,
                  "#{list_path(path)}: duplicate #{@find_by} #{key.inspect} " \
                  "(entries at index #{seen[key]} and #{index})"
          end
          seen[key] = index
        end
      end

      public

      # Wrap the shared import to insert duplicate detection up front.
      def import(parent, data, path:, importer:)
        entries = data.key?(@name.to_s) ? data[@name.to_s] : nil
        reject_duplicates!(entries, path) if entries.is_a?(Array)
        super
      end
    end
  end
end
