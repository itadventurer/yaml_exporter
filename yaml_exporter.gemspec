require_relative "lib/yaml_exporter/version"

Gem::Specification.new do |spec|
  spec.name        = "yaml_exporter"
  spec.version     = YamlExporter::VERSION
  spec.authors     = ["Anatoly Zelenin"]
  spec.email       = ["anatoly@zelenin.de"]

  spec.summary     = "YAML import/export for ActiveRecord models with a small declarative DSL"
  spec.description = "A Ruby gem that declaratively maps ActiveRecord models to YAML documents (and back) via a compact `attributes` / `one` / `many` DSL."
  spec.homepage    = "https://github.com/itadventurer/yaml_exporter"
  spec.license     = "MIT"

  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/itadventurer/yaml_exporter"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 5.2"
  spec.add_dependency "activesupport", ">= 5.2"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "sqlite3", ">= 1.4"
end
