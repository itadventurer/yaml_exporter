# frozen_string_literal: true

module YamlExporter
  # Walks a record + structure and emits the YAML document.
  #
  # Key order follows declaration order of the structure's nodes. List order
  # inside a `many` association is decided by the node itself.
  class Exporter
    def initialize(record, structure)
      @root_record = record
      @root_structure = structure
    end

    def to_yaml
      hash = build_hash(@root_record, @root_structure)
      YAML.dump(hash)
    end

    # Called recursively by nodes that own nested structures.
    def build_hash(record, structure)
      result = {}
      structure.nodes.each do |node|
        key, value = node.export(record, exporter: self)
        result[key] = value
      end
      result
    end
  end
end
