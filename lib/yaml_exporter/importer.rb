# frozen_string_literal: true

module YamlExporter
  # Drives the import of a YAML document into a tree of ActiveRecord records.
  #
  # Works in a single transaction on the root record's class. For every
  # record it touches (root + any owned child) it runs two phases:
  #
  #   1. pre_save  — nodes that mutate columns on *this* record
  #                  (Attribute, OneReference).
  #   2. save!     — the record is now persisted and has an id.
  #   3. post_save — nodes that need parent.id to do their work
  #                  (OneOwned, ManyPositional, ManyFindBy,
  #                   ManyReference, ManyThrough).
  #
  # Each node is responsible for its own persistence; this class just
  # orchestrates phases and validates unknown keys.
  class Importer
    def initialize(record, structure)
      @root_record = record
      @root_structure = structure
    end

    def import(yaml_string)
      @root_record.class.transaction do
        data = parse(yaml_string)
        apply(@root_record, @root_structure, data, path: '')
      end
      @root_record
    end

    # Called recursively by nodes that own child records (OneOwned,
    # ManyBase flavors) once they've built or found the child row.
    #
    # `extra_keys` lets the caller (typically a `many` node) declare keys
    # that belong to *it*, not to `structure`. Example: `find_by: :slug`
    # means `slug:` is legal at the entry level but isn't a declared
    # Attribute on the child — it's the discriminator the parent node
    # consumes. The child's own Attribute setters never see it because
    # no Attribute node declares it; it simply passes validation.
    def apply(record, structure, data, path:, extra_keys: [])
      data = {} if data.nil?
      unless data.is_a?(Hash)
        raise UnknownAttributeError, "#{describe_path(path)}: expected a mapping, got #{data.class}"
      end

      validate_keys!(structure, data, path: path, extra_keys: extra_keys)

      pre, post = structure.nodes.partition { |n| n.phase == :pre_save }
      pre.each { |n| n.import(record, data, path: path, importer: self) }
      record.save!
      post.each { |n| n.import(record, data, path: path, importer: self) }
    end

    private

    def parse(yaml_string)
      data = YAML.safe_load(
        yaml_string,
        permitted_classes: [Date, Time, Symbol],
        aliases: true
      )
      data = {} if data.nil?
      unless data.is_a?(Hash)
        raise UnknownAttributeError, "root: expected a mapping, got #{data.class}"
      end
      data
    end

    def validate_keys!(structure, data, path:, extra_keys: [])
      declared = structure.nodes.flat_map(&:yaml_keys).to_set
      extra_keys.each { |k| declared << k.to_s }
      unknown = data.keys.map(&:to_s).reject { |k| declared.include?(k) }
      return if unknown.empty?

      location = describe_path(path)
      unknown_list = unknown.map { |k| "'#{k}'" }.join(', ')
      raise UnknownAttributeError,
            "#{location}: unknown key#{unknown.size == 1 ? '' : 's'} #{unknown_list}"
    end

    def describe_path(path)
      path.empty? ? 'root' : path
    end
  end
end
