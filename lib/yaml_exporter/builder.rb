# frozen_string_literal: true

module YamlExporter
  # Evaluates a `yaml_structure do ... end` block via instance_eval and emits
  # a Structure. All declaration-time argument validation happens here (or
  # inside the constructors of the Node classes it delegates to).
  #
  # Accepts either a class or a callable that resolves to a class. The
  # callable form lets node constructors defer AR reflection lookups until
  # the inner block actually references the class (it doesn't, for
  # attribute-only blocks) — this matters for anonymous ActiveRecord
  # classes.
  class Builder
    def initialize(klass, &block)
      @klass_resolver = klass.respond_to?(:call) ? klass : -> { klass }
      @nodes = []
      instance_eval(&block) if block
    end

    def build
      Structure.new(klass: @klass_resolver, nodes: @nodes.freeze)
    end

    # ---- DSL ----------------------------------------------------------

    def attributes(*names)
      names.each { |n| @nodes << Nodes::Attribute.new(name: n, owner_class: @klass_resolver) }
    end

    def one(name, find_by: nil, &block)
      if block && find_by
        raise ArgumentError,
              "`one #{name.inspect}`: cannot combine a block (owned) with find_by: (reference). Pick one."
      end

      if block
        @nodes << Nodes::OneOwned.new(name: name, owner_class: klass, &block)
      elsif find_by
        @nodes << Nodes::OneReference.new(name: name, owner_class: klass, find_by: find_by)
      else
        raise ArgumentError,
              "`one #{name.inspect}`: must pass either find_by: (reference) or a block (owned)."
      end
    end

    def many(name, find_by: nil, through: nil, positioned_by: nil, &block)
      if positioned_by && !block
        raise ArgumentError,
              "`many #{name.inspect}`: positioned_by: requires a block — the column lives on the owned record."
      end

      if through
        unless find_by
          raise ArgumentError,
                "`many #{name.inspect}`: through: requires find_by: to resolve the target."
        end
        unless block
          raise ArgumentError,
                "`many #{name.inspect}`: through: requires a block — join attributes live in it."
        end
        @nodes << Nodes::ManyThrough.new(
          name: name, owner_class: klass, through: through, find_by: find_by,
          positioned_by: positioned_by, &block
        )
      elsif block && find_by
        @nodes << Nodes::ManyFindBy.new(
          name: name, owner_class: klass, find_by: find_by,
          positioned_by: positioned_by, &block
        )
      elsif block
        @nodes << Nodes::ManyPositional.new(
          name: name, owner_class: klass, positioned_by: positioned_by, &block
        )
      elsif find_by
        @nodes << Nodes::ManyReference.new(name: name, owner_class: klass, find_by: find_by)
      else
        raise ArgumentError,
              "`many #{name.inspect}`: pass either find_by: (reference list), a block (owned), " \
              'or both / through: + find_by: + block.'
      end
    end

    private

    def klass
      @klass ||= @klass_resolver.call
    end
  end
end
