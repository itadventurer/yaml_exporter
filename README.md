# YamlExporter

YamlExporter is a Ruby gem that provides YAML serialization and deserialization functionality for ActiveRecord models,
with JSON schema generation for validation.

## Features

- Serialize ActiveRecord models to YAML
- Deserialize YAML back to ActiveRecord models
- Generate JSON schemas for model validation
- Support for nested associations (has_many and has_one)
- Automatic type inference based on database column types

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'yaml_exporter'
```

And then execute:

```
$ bundle install
```

Or install it yourself as:

```
$ gem install yaml_exporter
```

## Usage

### Setting up your model

Include the `YamlExporter` module in your ActiveRecord model and define the YAML structure:

```ruby

class Quiz < ApplicationRecord
  include YamlExporter

  yaml_structure do
    yaml_attribute :title, :quiz_type
    yaml_has_many :questions do
      yaml_attribute :text, :question_type, :feedback
      yaml_has_many :answers do
        yaml_attribute :text, :is_correct, :impact
      end
    end
  end
end
```

### Serializing to YAML

To serialize a model instance to YAML:

```ruby
quiz = Quiz.find(1)
yaml_string = quiz.yaml_export
```

### Deserializing from YAML

To deserialize YAML back to a model instance:

```ruby
quiz = Quiz.new
quiz.yaml_import(yaml_string)
```

### Generating JSON Schema

To generate a JSON schema for validation:

```ruby
schema = Quiz.yaml_schema
```

## Configuration

The YamlExporter automatically infers types based on the database column types. JSON and JSONB columns are treated as
objects in the generated schema.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/itadventurer/yaml_exporter.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).