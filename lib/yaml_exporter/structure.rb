# frozen_string_literal: true

module YamlExporter
  # Immutable representation of a `yaml_structure do ... end` block.
  #
  # * `klass` — the ActiveRecord class this structure is attached to.
  #   Resolved lazily: the constructor accepts either a class or a callable,
  #   and defers to first access. This matters for inner structures whose
  #   class might be resolved via a reflection that isn't safe to compute
  #   at declaration time (anonymous parent classes, etc.).
  # * `nodes` — ordered list of node objects. Order matches declaration and
  #   drives export key order.
  class Structure
    attr_reader :nodes

    def initialize(klass:, nodes:)
      @klass_resolver = klass.respond_to?(:call) ? klass : -> { klass }
      @nodes = nodes
    end

    def klass
      @klass ||= @klass_resolver.call
    end
  end
end
