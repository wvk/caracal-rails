module Caracal
  module Rails
    class TemplateHandler
      
      # Returns the code Rails compiles into the view's method: the view's
      # source inside the block Tilt::CaracalTemplate wraps it in, where docx
      # is a DocumentWrapper around the document. The source starts on the
      # block's first line, so an error on line N of the view reports line N.
      #
      def self.call(template, source)
        "Caracal::Document.render do |docx|; docx = Caracal::Rails::DocumentWrapper.new(docx); #{ source }\nend"
      end
      
    end
  end
end
