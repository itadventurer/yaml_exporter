# frozen_string_literal: true

require 'active_record'
require 'active_support/core_ext/class/attribute'

require_relative 'yaml_exporter/version'

# Top-level entrypoint: defines the `include YamlExporter` hook and the
# public API methods (`yaml_structure`, `yaml_schema`, `yaml_import`,
# `yaml_export`). Parsing, import, export and schema generation live in
# dedicated classes under `lib/yaml_exporter/`.
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
      self.yaml_structure_definition = YamlExporter::Builder.new(self, &block).build
      include InstanceMethods
    end

    def yaml_schema
      YamlExporter::Schema.generate(yaml_structure_definition)
    end
  end

  module InstanceMethods
    def yaml_import(yaml_string)
      YamlExporter::Importer.new(self, self.class.yaml_structure_definition).import(yaml_string)
    end

    # `omit_nil:` (default true) drops keys whose value is empty — a nil
    # attribute, a missing `one` reference, an absent owned `one`, or an empty
    # `many` list. Round-trip safe: import treats a missing key, an explicit
    # `null`, and an empty list identically. Pass `omit_nil: false` to keep
    # explicit `null`s in the file (e.g. so optional fields stay discoverable).
    def yaml_export(omit_nil: true)
      YamlExporter::Exporter.new(
        self, self.class.yaml_structure_definition, omit_nil: omit_nil
      ).to_yaml
    end
  end
end

require 'set'
require 'yaml'

require_relative 'yaml_exporter/structure'
require_relative 'yaml_exporter/type_inference'
require_relative 'yaml_exporter/nodes/attribute'
require_relative 'yaml_exporter/nodes/of_resolution'
require_relative 'yaml_exporter/nodes/one_owned'
require_relative 'yaml_exporter/nodes/one_reference'
require_relative 'yaml_exporter/nodes/one_reference_of'
require_relative 'yaml_exporter/nodes/many_base'
require_relative 'yaml_exporter/nodes/many_positional'
require_relative 'yaml_exporter/nodes/many_find_by'
require_relative 'yaml_exporter/nodes/many_reference'
require_relative 'yaml_exporter/nodes/many_through'
require_relative 'yaml_exporter/builder'
require_relative 'yaml_exporter/importer'
require_relative 'yaml_exporter/exporter'
require_relative 'yaml_exporter/schema'
