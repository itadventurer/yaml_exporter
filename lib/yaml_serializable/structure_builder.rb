# frozen_string_literal: true

module YamlSerializable
  class StructureBuilder
    def initialize(&block)
      @structure = { attributes: [], associations: {} }
      instance_eval(&block)
    end

    def yaml_attribute(*attrs)
      @structure[:attributes].concat(attrs)
    end

    def yaml_has_one(name, &block)
      @structure[:associations][name] = { type: :has_one, structure: self.class.new(&block).build }
    end

    def yaml_has_many(name, &block)
      @structure[:associations][name] = { type: :has_many, structure: self.class.new(&block).build }
    end

    def yaml_condition(&block)
      @structure[:condition] = block
    end

    def build
      @structure
    end
  end
end