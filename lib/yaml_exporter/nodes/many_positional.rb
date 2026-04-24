# frozen_string_literal: true

module YamlExporter
  module Nodes
    # `many :assoc do ... end` — identity is positional (array index). The
    # documented footgun: reordering the YAML list rewrites existing rows
    # in place by index instead of swapping ids.
    class ManyPositional < ManyBase
      def find_or_build_child(parent, _entry, index, existing:)
        existing[index] || build_child(parent)
      end
    end
  end
end
