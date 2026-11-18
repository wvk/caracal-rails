require 'active_support/lazy_load_hooks'
require 'nokogiri'
require 'stringio'
require 'uri'
require 'zip'

module Caracal
  module Rails
    # RSpec matchers and Minitest assertions for DOCX responses. Requiring
    # this file includes them in every RSpec example group and in
    # ActiveSupport::TestCase, the base class of Rails' integration,
    # controller, mailer and job tests.
    #
    #   expect(response).to be_docx.named('Bericht März.docx')
    #   assert_docx response, filename: 'Bericht März.docx'
    #
    # The helpers take a response, or a DOCX as a String. The module holds
    # methods only, so test classes that include it keep their constants.
    module TestHelpers
      # The text of the document body, one line per paragraph.
      def docx_text(docx)
        docx_paragraphs(docx).map(&:last).join("\n")
      end

      # The paragraphs of the document body as [style id, text] pairs.
      def docx_paragraphs(docx)
        DocxReader.new(docx).paragraphs
      end

      # Passes for a response with the DOCX media type and a body that is a
      # DOCX package, or for a String that is one. `named` also compares the
      # file name in the response's Content-Disposition.
      def be_docx
        DocxMatcher.new
      end

      # Minitest's counterpart of be_docx.
      def assert_docx(docx, filename: nil)
        matcher = filename ? be_docx.named(filename) : be_docx
        assert matcher.matches?(docx), -> { matcher.failure_message }
      end
    end


    # The matcher behind TestHelpers#be_docx and #assert_docx.
    class DocxMatcher
      def named(filename)
        @filename = filename
        self
      end

      def matches?(actual)
        @mismatch = DocxReader.new(actual).mismatch(@filename)
        @mismatch.nil?
      end

      def failure_message
        "expected #{ expected }, but #{ @mismatch }"
      end

      def failure_message_when_negated
        "did not expect #{ expected }"
      end

      def description
        "be #{ expected }"
      end

      private

      def expected
        @filename ? "a DOCX named #{ @filename.inspect }" : 'a DOCX'
      end
    end


    # Reads a response or a String as a DOCX, for TestHelpers.
    class DocxReader
      MEDIA_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      NAMESPACES = {
        'w'  => 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
        'mc' => 'http://schemas.openxmlformats.org/markup-compatibility/2006'
      }

      # word/document.xml holds the text of a frame twice: in a text box,
      # and in a VML copy under mc:Fallback for older readers.
      PARAGRAPHS = '//w:body//w:p[not(ancestor::mc:Fallback)]'

      # Text, tabs and line breaks; page and column breaks add no text.
      CONTENT = './/w:r/w:t | .//w:r/w:tab | .//w:r/w:br[not(@w:type) or @w:type = "textWrapping"]'

      # A parameter of a Content-Disposition: its name, then its value as a
      # quoted string or as a token.
      PARAMETER = /(?:\A|;)\s*([^=;\s"]+)\s*=\s*(?:"((?:\\.|[^"\\])*)"|([^;]*))/

      NotDocx = Class.new(StandardError)

      def initialize(docx)
        @response = docx if docx.respond_to?(:body) && docx.respond_to?(:media_type)
        @body     = @response ? @response.body : docx
      end

      def paragraphs
        Nokogiri::XML(document_xml).xpath(PARAGRAPHS, NAMESPACES).map do |paragraph|
          [paragraph.at_xpath('w:pPr/w:pStyle/@w:val', NAMESPACES)&.value, text(paragraph)]
        end
      rescue NotDocx => e
        raise ArgumentError, "expected a DOCX, but #{ e.message }"
      end

      # Why this is no DOCX, or no DOCX named +filename+; nil if it is one.
      def mismatch(filename)
        if @response && @response.media_type != MEDIA_TYPE
          return "the media type is #{ @response.media_type.inspect }"
        end

        document_xml
        filename_mismatch(filename) if filename
      rescue NotDocx => e
        e.message
      end

      private

      def document_xml
        @document_xml ||= begin
          unless @body.is_a?(String)
            raise NotDocx, "got #{ @body.nil? ? 'nil' : "an instance of #{ @body.class }" }; the helpers read a response or a String"
          end
          raise NotDocx, 'the body is empty' if @body.empty?

          zip   = Zip::File.open_buffer(StringIO.new(@body))
          entry = zip.find_entry('word/document.xml')
          raise NotDocx, "the body is a ZIP archive without word/document.xml: #{ zip.entries.map(&:name).join(', ') }" unless entry

          entry.get_input_stream.read
        rescue Zip::Error
          raise NotDocx, "the body is not a ZIP archive and starts with #{ @body.byteslice(0, 40).inspect }"
        end
      end

      # The paragraph's own text. The text of a frame anchored in it belongs
      # to the frame's paragraphs.
      def text(paragraph)
        depth = paragraph.xpath('count(ancestor-or-self::w:p)', NAMESPACES).to_i

        paragraph.xpath("(#{ CONTENT })[count(ancestor::w:p) = #{ depth }]", NAMESPACES).map do |node|
          case node.name
          when 't'   then node.text
          when 'tab' then "\t"
          else            "\n"
          end
        end.join
      end

      def filename_mismatch(filename)
        return 'got a String, which carries no file name' unless @response

        disposition = @response.headers['Content-Disposition']
        return 'the response has no Content-Disposition header' if disposition.nil?

        actual = filename_in(disposition)
        if actual.nil?
          "the Content-Disposition names no file: #{ disposition }"
        elsif actual != filename
          "the file name is #{ actual.inspect } (Content-Disposition: #{ disposition })"
        end
      end

      # filename* (RFC 6266, encoded as RFC 5987 describes) when present,
      # else filename. Reading whole parameters keeps text inside a quoted
      # string from passing for a parameter.
      def filename_in(disposition)
        parameters = {}
        disposition.scan(PARAMETER) do |name, quoted, token|
          parameters[name.downcase] ||= quoted ? quoted.gsub(/\\(.)/, '\1') : token.strip
        end
        return parameters['filename'] unless parameters['filename*']

        charset, _language, encoded = parameters['filename*'].split("'", 3)
        URI.decode_uri_component(encoded.to_s, Encoding.find(charset.to_s)).encode(Encoding::UTF_8)
      rescue ArgumentError, EncodingError => e
        raise NotDocx, "the filename* of the Content-Disposition cannot be decoded (#{ e.message }): #{ disposition }"
      end
    end
  end
end


RSpec.configure { |config| config.include Caracal::Rails::TestHelpers } if defined?(RSpec.configure)

ActiveSupport.on_load(:active_support_test_case) { include Caracal::Rails::TestHelpers }
