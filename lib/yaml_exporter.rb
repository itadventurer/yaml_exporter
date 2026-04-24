# frozen_string_literal: true

require_relative 'yaml_serializable/structure_builder'
require_relative 'yaml_serializable/yaml_exporter'

module YamlExporter
  # Base class for every library-specific error. Inherits from
  # ActiveRecord::ActiveRecordError so existing `rescue ActiveRecord::ActiveRecordError`
  # blocks (and the import transaction wrapper) catch it naturally.
  class Error < ActiveRecord::ActiveRecordError; end

  # Raised when a YAML document carries a key (top-level or inside an entry)
  # that the corresponding `yaml_structure` scope does not declare.
  class UnknownAttributeError < Error; end

  # Raised when a `find_by`-identified list contains two entries with the same
  # key value — e.g. two `slug: chapter-1` entries under one `book_parts:`.
  class DuplicateKeyError < Error; end

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def yaml_structure(&block)
      class_attribute :yaml_structure_definition, instance_writer: false
      self.yaml_structure_definition = YamlSerializable::StructureBuilder.new(&block).build
      include InstanceMethods
    end

    def yaml_schema
      YamlSerializable::YamlExporter.generate_schema(self, yaml_structure_definition)
    end
  end

  module InstanceMethods
    def yaml_export
      YamlSerializable::YamlExporter.export(self, self.class.yaml_structure_definition)
    end

    def yaml_import(yaml_string)
      YamlSerializable::YamlExporter.import(self, yaml_string, self.class.yaml_structure_definition)
    end
  end
end
