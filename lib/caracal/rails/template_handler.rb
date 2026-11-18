module Caracal
  module Rails
    class TemplateHandler
      
      # Returns the code Rails compiles into the view's method: the view's
      # source in a block that TemplateHandler.render calls with docx. The
      # source starts on the block's first line, so an error on line N of the
      # view reports line N.
      #
      def self.call(template, source)
        "Caracal::Rails::TemplateHandler.render(self) do |docx|; #{ source }\nend"
      end
      
      # Runs a view's code with docx, a DocumentWrapper. The outermost view
      # creates the document, keeps docx on the view while it renders, and
      # returns the DOCX. The views it renders, such as partials, collections
      # and templates, add to that document through the same docx and return
      # an empty String.
      #
      def self.render(view)
        if (docx = view.instance_variable_get(:@_caracal_docx))
          yield docx
          return ''
        end

        Caracal::Document.render do |document|
          docx = DocumentWrapper.new(document)
          view.instance_variable_set(:@_caracal_docx, docx)
          yield docx
        ensure
          view.instance_variable_set(:@_caracal_docx, nil)
        end
      end
      
    end
  end
end
