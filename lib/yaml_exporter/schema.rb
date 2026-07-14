# frozen_string_literal: true

module YamlExporter
  # Builds a JSON-schema-ish hash describing a structure. Keys are symbols
  # so callers can use `schema[:properties][:title]` ergonomically.
  class Schema
    def self.generate(structure)
      new(structure).generate
    end

    def initialize(structure)
      @structure = structure
    end

    def generate
      {
        type: 'object',
        properties: @structure.nodes.each_with_object({}) do |node, acc|
          acc.merge!(node.schema_fragment)
        end
      }
    end
  end
end
