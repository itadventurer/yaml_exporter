# frozen_string_literal: true

module YamlExporter
  # Marker subclass: a String that must be emitted as a YAML literal block
  # scalar (`|`). Attribute nodes wrap the values of `text` columns in this so
  # the Exporter's visitor can render them as block scalars regardless of
  # length, while `string`/varchar columns stay inline.
  #
  # Trailing whitespace on a line (a space/tab before a newline) makes
  # libyaml's emitter refuse block style and silently fall back to a
  # double-quoted inline scalar — which is exactly what breaks the "text
  # columns are always block scalars" promise. Such whitespace is virtually
  # always an accidental typo, so we strip it per line on construction. This
  # also normalizes CR (`\r\n`/`\r`), which trips the same fallback.
  class LiteralString < ::String
    def self.new(value)
      super(normalize(value.to_s))
    end

    def self.normalize(value)
      value.split("\n", -1).map(&:rstrip).join("\n")
    end
  end

  # Walks a record + structure and emits the YAML document.
  #
  # Key order follows declaration order of the structure's nodes. List order
  # inside a `many` association is decided by the node itself.
  #
  # `omit_nil` (an export-time option, passed from `yaml_export`) drops keys
  # whose exported value is "empty": nil, or an empty list. This is round-trip
  # safe because import treats a missing key, an explicit `null`, and an empty
  # list identically. An owned child that exists but has only nil attributes
  # exports as `{}` and is kept — omitting it would mean "destroy" on
  # re-import.
  class Exporter
    def initialize(record, structure, omit_nil: true)
      @root_record = record
      @root_structure = structure
      @omit_nil = omit_nil
    end

    def to_yaml
      hash = build_hash(@root_record, @root_structure)
      dump(hash)
    end

    # Called recursively by nodes that own nested structures.
    def build_hash(record, structure)
      result = {}
      structure.nodes.each do |node|
        key, value = node.export(record, exporter: self)
        next if @omit_nil && omit?(value)

        result[key] = value
      end
      result
    end

    private

    def omit?(value)
      value.nil? || (value.is_a?(Array) && value.empty?)
    end

    def dump(hash)
      visitor = BlockScalarTree.create
      visitor << hash
      visitor.tree.yaml
    end

    # Renders any LiteralString value as a literal block scalar (`|`). Plain
    # Strings and every other type fall through to Psych's default handling,
    # so the output is byte-identical to `YAML.dump` whenever no LiteralString
    # is present.
    class BlockScalarTree < Psych::Visitors::YAMLTree
      def accept(target)
        if target.is_a?(LiteralString)
          return @emitter.scalar(target.to_s, nil, nil, true, true, Psych::Nodes::Scalar::LITERAL)
        end

        super
      end
    end
  end
end
