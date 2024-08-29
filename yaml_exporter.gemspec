require_relative "lib/yaml_serializable/version"

Gem::Specification.new do |spec|
  spec.name        = "yaml_exporter"
  spec.version     = YamlSerializable::VERSION
  spec.authors     = ["Anatoly Zelenin"]
  spec.email       = ["anatoly@zelenin.de"]

  spec.summary     = "YAML serialization for ActiveRecord models with JSON schema support"
  spec.description = "A Ruby gem for YAML serialization and deserialization of ActiveRecord models with JSON schema generation."
  spec.homepage    = "https://github.com/itadventurer/yaml_exporter"
  spec.license     = "MIT"

  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/itadventurer/yaml_exporter"
  #spec.metadata["changelog_uri"] = "https://github.com/itadventurer/yaml_exporter/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 5.2"
  spec.add_dependency "activesupport", ">= 5.2"

  spec.add_development_dependency "rake", "~> 13.0"
end