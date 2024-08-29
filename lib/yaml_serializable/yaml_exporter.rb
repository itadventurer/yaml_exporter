require 'yaml'
require 'json-schema'

module YamlSerializable
  class YamlExporter
    def self.export(object, structure)
      new(object, structure).export
    end

    def self.import(object, yaml_string, structure)
      new(object, structure).import(yaml_string)
    end

    def self.generate_schema(klass, structure)
      new(klass.new, structure).generate_schema
    end

    def initialize(object, structure)
      @object = object
      @structure = structure
    end

    def export
      yaml = YAML.dump(build_hash(@structure, @object))
      validate(yaml)
      yaml
    end

    def import(yaml_string)
      data = YAML.safe_load(yaml_string)
      validate(yaml_string)
      update_object(data)
      @object
    end

    def generate_schema
      {
        type: 'object',
        properties: generate_properties(@structure, @object.class),
        required: required_attributes(@structure, @object.class)
      }
    end

    private

    def build_hash(structure, object)
      result = {}

      structure[:attributes].each do |attr|
        value = object.send(attr)
        result[attr.to_s] = value unless value.nil?
      end

      structure[:associations].each do |name, config|
        if config[:type] == :has_many
          associated_objects = object.send(name).unscope(:order).order(:id)
          if associated_objects.any?
            result[name.to_s] = associated_objects.map { |item| build_hash(config[:structure], item) }
          end
        elsif config[:type] == :has_one
          associated_object = object.send(name)
          result[name.to_s] = build_hash(config[:structure], associated_object) if associated_object
        end
      end

      result.compact
    end

    def validate(yaml)
      schema = generate_schema
      data = YAML.safe_load(yaml)
      JSON::Validator.validate!(schema, data)
    rescue JSON::Schema::ValidationError => e
      raise "Invalid YAML structure: #{e.message}"
    end

    def update_object(data)
      @object.transaction do
        update_attributes(@object, data, @structure[:attributes])
        @structure[:associations].each do |name, config|
          if config[:type] == :has_many
            update_collection(@object, data[name.to_s], name, config[:structure])
          elsif config[:type] == :has_one && data[name.to_s]
            update_nested(@object, data[name.to_s], name, config[:structure])
          end
        end
        @object.save!
      end
    end

    def update_attributes(object, data, attributes)
      attributes.each do |attr|
        if data.key?(attr.to_s)
          object.send("#{attr}=", data[attr.to_s])
        else
          object.send("#{attr}=", nil)
        end
      end
    end

    def update_collection(parent, items_data, association_name, config)
      existing_items = parent.send(association_name).unscope(:order).order(:id).to_a
      new_items = []

      items_data&.each_with_index do |item_data, index|
        item = existing_items[index] || parent.send(association_name).build
        update_attributes(item, item_data, config[:attributes])
        config[:associations]&.each do |sub_name, sub_config|
          if sub_config[:type] == :has_many
            update_collection(item, item_data[sub_name.to_s], sub_name, sub_config[:structure])
          elsif sub_config[:type] == :has_one && item_data[sub_name.to_s]
            update_nested(item, item_data[sub_name.to_s], sub_name, sub_config[:structure])
          end
        end
        new_items << item
      end

      # Entferne Items, die nicht mehr im YAML vorhanden sind
      (existing_items - new_items).each(&:mark_for_destruction)

      parent.send("#{association_name}=", new_items)
    end

    def update_nested(parent, nested_data, association_name, config)
      nested_object = parent.send(association_name) || parent.send("build_#{association_name}")
      update_attributes(nested_object, nested_data, config[:attributes])
      config[:associations]&.each do |sub_name, sub_config|
        if sub_config[:type] == :has_many
          update_collection(nested_object, nested_data[sub_name.to_s], sub_name, sub_config[:structure])
        elsif sub_config[:type] == :has_one && nested_data[sub_name.to_s]
          update_nested(nested_object, nested_data[sub_name.to_s], sub_name, sub_config[:structure])
        end
      end
    end

    def generate_properties(structure, klass)
      properties = {}

      structure[:attributes].each do |attr|
        column = klass.columns_hash[attr.to_s]
        properties[attr.to_s] = { type: infer_type(column) }
      end

      structure[:associations].each do |name, config|
        if config[:type] == :has_many
          properties[name.to_s] = {
            type: 'array',
            items: {
              type: 'object',
              properties: generate_properties(config[:structure], association_class(klass, name)),
              required: required_attributes(config[:structure], association_class(klass, name))
            }
          }
        elsif config[:type] == :has_one
          properties[name.to_s] = {
            type: 'object',
            properties: generate_properties(config[:structure], association_class(klass, name)),
            required: required_attributes(config[:structure], association_class(klass, name))
          }
        end
      end

      properties
    end

    def infer_type(column)
      case column.type
      when :string, :text
        'string'
      when :integer, :bigint
        'integer'
      when :float, :decimal
        'number'
      when :boolean
        'boolean'
      when :date, :datetime, :time
        'string'
      when :json, :jsonb
        'object'
      else
        'string'
      end
    end

    def association_class(klass, association_name)
      klass.reflect_on_association(association_name).klass
    end

    def required_attributes(structure, klass)
      structure[:attributes].select do |attr|
        column = klass.columns_hash[attr.to_s]
        column && !column.null
      end
    end
  end
end
