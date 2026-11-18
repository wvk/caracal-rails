module Caracal
  module Rails
    # Stands in for the Caracal::Document in views. While the block of a
    # header, footer or frame runs, the commands that add content go to
    # that container, so helpers and partials that receive docx write
    # where their caller is. wvk/caracal#62 proposes the same for caracal.
    class DocumentWrapper

      # The commands that add content. They go to the innermost open
      # container, else to the document; all other commands go to the
      # document.
      CONTENT_COMMANDS = %i(p h1 h2 h3 h4 h5 h6 table img ol ul hr page column_break
                            iframe bookmark_start bookmark_end raw_xml table_of_contents toc).freeze

      attr_reader :document

      def initialize(document)
        @document   = document
        @containers = []
      end

      CONTENT_COMMANDS.each do |command|
        define_method command do |*args, **options, &block|
          target.public_send command, *args, **options, &block
        end
      end

      # Returns the header; with a block, the header is open while it runs.
      def header(**options, &block)
        return document.header(**options) unless block

        document.header(**options) {|part| within part, block }
      end

      # Returns the footer; with a block, the footer is open while it runs.
      def footer(**options, &block)
        return document.footer(**options) unless block

        document.footer(**options) {|part| within part, block }
      end

      # Adds a frame to the innermost open container, else to the document.
      # The frame is open while its block runs.
      def frame(options = {}, &block)
        return target.frame(options) unless block

        target.frame(options) {|frame| within frame, block }
      end

      # The section's header: and footer: blocks open their part like
      # header and footer do. A block with a parameter receives the
      # wrapper in place of the document.
      def section(options = {}, &block)
        if options.is_a? Hash
          options = options.merge options.slice(:header, :footer).transform_values {|value| opening value }
        end

        if block and block.arity >= 1
          view_block = block
          block      = proc {|_document| view_block[self] }
        end

        document.section options, &block
      end

      def method_missing(name, ...)
        document.public_send(name, ...)
      end

      def respond_to_missing?(name, include_private = false)
        document.respond_to?(name) || super
      end

      private

      # The innermost open container, else the document.
      def target
        @containers.last || document
      end

      # Runs the view's block as caracal does, called with the container
      # or evaluated inside it, and keeps the container open meanwhile.
      def within(container, block)
        @containers.push container
        (block.arity < 1) ? container.instance_exec(&block) : block[container]
      ensure
        @containers.pop
      end

      # Turns the blocks among a section's header: or footer: option, which
      # is a block, a part or a hash of these, into blocks that open their part.
      def opening(value)
        case value
        when Proc then ->(part) { within part, value }
        when Hash then value.transform_values {|given| opening given }
        else value
        end
      end

    end
  end
end
