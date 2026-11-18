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

      it 'wraps the source in a block that render calls with docx and starts on its first line' do
        expect(actual).to eq "Caracal::Rails::TemplateHandler.render(self) do |docx|; docx.h1 'Quarterly Report'\ndocx.p 'Lorem ipsum'\n\nend"
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
          expect(actual).to eq %Q{Caracal::Rails::TemplateHandler.render(self) do |docx|; docx.p "\#{ @client.name }'s report"\nend}
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

    # The views are in spec/dummy/app/views.
    describe 'views rendered inside a view' do
      it 'adds a partial to the document of the view, and the partial returns an empty String' do
        expect(docx_paragraphs(render_docx('reports/outer'))).to eq [
          ['Heading1', 'Outer'],
          ['Normal',   'Inner'],
          ['Normal',   'partial returned String of 0 bytes']
        ]
      end

      it 'adds a section per item of a collection, with the item as its local' do
        client = Struct.new(:name, :city)
        docx   = render_docx('reports/clients', locals: { clients: [client.new('ACME GmbH', 'Kiel'), client.new('Beta AG', 'Hamburg')] })

        expect(docx_paragraphs(docx)).to eq [
          ['Heading1', 'Clients'],
          ['Heading2', 'ACME GmbH'], ['Normal', 'Kiel'],
          ['Heading2', 'Beta AG'],   ['Normal', 'Hamburg']
        ]
      end

      it 'adds a template rendered with render template: to the document' do
        expect(docx_paragraphs(render_docx('reports/combined'))).to eq [['Heading1', 'Included'], ['Normal', 'After the template']]
      end

      describe 'in header and frame blocks' do
        let(:docx) { render_docx('offers/partials', locals: { number: '2026-118' }) }

        it 'adds a partial rendered in a header block to the header, with the partials it renders' do
          expect(docx_text(docx, part: 'word/header1.xml')).to eq "ACME GmbH\nKiel"
        end

        it 'adds a partial rendered in a frame block to the frame' do
          expect(docx_paragraphs(docx)).to eq [[nil, ''], ['Normal', 'Offer 2026-118'], ['Normal', 'Body text']]
        end
      end

      # The view context renders as a view of another format, such as HTML,
      # does.
      describe 'outside a .docx.caracal view' do
        let(:view) { ApplicationController.new.view_context }

        it 'renders a partial into a document of its own' do
          expect(docx_paragraphs(view.render(partial: 'reports/inner', formats: [:docx]))).to eq [['Normal', 'Inner']]
        end

        it 'starts a new document after an exception in a partial' do
          # Line 2 of reports/_failing.docx.caracal raises.
          expect { view.render(template: 'reports/failing', formats: [:docx]) }.to raise_error(ActionView::Template::Error, 'no data') { |error|
            expect(error.backtrace.first).to start_with "#{ Rails.root }/app/views/reports/_failing.docx.caracal:2:"
          }

          expect(docx_text(view.render(template: 'reports/outer', formats: [:docx]))).to eq "Outer\nInner\npartial returned String of 0 bytes"
        end
      end
    end

  end
  
end