require 'spec_helper'

describe Caracal::Rails::TemplateHandler do
    
  #--------------------------------------------------------
  # Class Methods
  #--------------------------------------------------------
  
  describe 'class method tests' do
    
    # .call
    describe '#call' do
      let(:template) { double('template', identifier: '/app/views/reports/show.docx.caracal') }
      let(:source)   { "docx.h1 'Quarterly Report'\ndocx.p 'Lorem ipsum'\n" }
      let(:actual)   { Caracal::Rails::TemplateHandler.call(template, source) }

      it 'wraps the source in a document block that starts on its first line' do
        expect(actual).to eq "Caracal::Document.render do |docx|; docx.h1 'Quarterly Report'\ndocx.p 'Lorem ipsum'\n\nend"
      end

      describe 'when the path is hostile' do
        let(:template) { double('template', identifier: %q{/tmp/x'); system('id'); ('}) }

        it 'keeps the path out of the generated code' do
          expect(actual).not_to include('/tmp/x', 'system')
        end
      end

      describe 'when the source contains quotes and interpolation' do
        let(:source) { %q{docx.p "#{ @client.name }'s report"} }

        it 'passes them through as code, as ERB does with the code in its tags' do
          expect(actual).to eq %Q{Caracal::Document.render do |docx|; docx.p "\#{ @client.name }'s report"\nend}
        end

        it 'produces source that parses as ruby' do
          expect { RubyVM::InstructionSequence.compile(actual) }.not_to raise_error
        end
      end
    end
    
  end
  
  
  #--------------------------------------------------------
  # Rendering
  #--------------------------------------------------------
  
  describe 'rendering tests' do
    
    def render_docx(template, **options)
      ApplicationController.render(template: template, formats: [:docx], **options)
    end

    it 'passes locals to the view' do
      docx = render_docx('reports/locals', locals: { title: 'From locals' })

      expect(docx_paragraphs(docx)).to eq [['Heading1', 'From locals']]
    end

    it 'renders a view again without compiling it or reading its file' do
      render_docx('reports/locals', locals: { title: 'First' })
      allow(Caracal::Rails::TemplateHandler).to receive(:call).and_call_original
      allow(File).to receive(:binread).and_call_original

      docx = render_docx('reports/locals', locals: { title: 'Second' })

      expect(docx_text(docx)).to eq 'Second'
      expect(Caracal::Rails::TemplateHandler).not_to have_received(:call)
      expect(File).not_to have_received(:binread).with(end_with('reports/locals.docx.caracal'))
    end

    it 'reports the line of the view on which an error occurs' do
      # Line 3 of reports/broken.docx.caracal calls a method on nil.
      expect { render_docx('reports/broken') }.to raise_error(ActionView::Template::Error) { |error|
        expect(error.line_number).to eq '3'
        expect(error.backtrace.first).to start_with "#{ Rails.root }/app/views/reports/broken.docx.caracal:3:"
      }
    end

    describe 'when the view comes from a resolver other than the file system' do
      let(:resolver) { ActionView::FixtureResolver.new('reports/fixture.docx.caracal' => "docx.h1 'From fixture'") }

      # The view paths of ApplicationController apply to every controller of
      # the dummy app; the example restores them.
      around do |example|
        view_paths = ApplicationController.view_paths
        ApplicationController.prepend_view_path(resolver)
        example.run
      ensure
        ApplicationController.view_paths = view_paths
      end

      it 'renders it' do
        expect(docx_paragraphs(render_docx('reports/fixture'))).to eq [['Heading1', 'From fixture']]
      end
    end
    
  end
  
end