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

      # clients/_summary.docx.caracal is the dummy app's. The test
      # environment turns caching off, and Rails.cache, a memory store, holds
      # the fragments.
      describe 'with fragment caching' do
        let(:client)  { Struct.new(:name, :city) }
        let(:clients) { [client.new('ACME GmbH', 'Kiel'), client.new('Beta AG', 'Hamburg')] }
        let(:resolver) do
          ActionView::FixtureResolver.new(
            'reports/cache_block.docx.caracal'       => "docx.h1 'Clients'\ncache('clients/intro') { docx.p 'Our clients by city' }",
            'reports/cache_if.docx.caracal'          => "cache_if(false, 'clients/intro') { docx.p 'Our clients by city' }",
            'reports/cache_unless.docx.caracal'      => "cache_unless(true, 'clients/intro') { docx.p 'Our clients by city' }",
            'reports/cached_clients.docx.caracal'    => "render partial: 'clients/summary', collection: clients, as: :client, cached: true",
            'reports/uncached_clients.docx.caracal'  => "render partial: 'clients/summary', collection: clients, as: :client, cached: false",
            'reports/cache_in_partial.docx.caracal'  => "docx.h1 'Clients'\nrender 'reports/cached_intro'",
            'reports/_cached_intro.docx.caracal'     => "cache('clients/intro') { docx.p 'Our clients by city' }",
            'reports/greeting.html.erb'              => "<% cache('greeting', skip_digest: true) do %>Hello <%= name %><% end %>",
            'reports/with_greeting.docx.caracal'     => "docx.p render(partial: 'reports/greeting', formats: [:html], locals: { name: name })",
            'reports/_greeting.html.erb'             => "<% cache('greeting', skip_digest: true) do %>Hello <%= name %><% end %>",
            'reports/with_lines.docx.caracal'        => "docx.p render(partial: 'reports/lines', formats: [:html], locals: { clients: clients, year: year })",
            'reports/_lines.html.erb'                => "<%= render partial: 'reports/line', collection: clients, as: :client, cached: true, locals: { year: year } %>",
            'reports/_line.html.erb'                 => "<%= client.name %> <%= year %>;",
            'reports/cache_in_layout_block.docx.caracal' => "render(layout: 'reports/box') { cache('clients/intro') { docx.p 'Our clients by city' } }",
            'reports/_box.docx.caracal'              => "docx.p 'Top'\nyield"
          )
        end

        around do |example|
          view_paths = ApplicationController.view_paths
          ApplicationController.prepend_view_path(resolver)
          Rails.cache.clear
          example.run
        ensure
          ApplicationController.view_paths = view_paths
          Rails.cache.clear
        end

        def raise_fragment_caching_error(helper)
          raise_error(ActionView::Template::Error, start_with("#{ helper } in a .docx.caracal view")) { |error|
            expect(error.cause).to be_a Caracal::Rails::FragmentCachingError
          }
        end

        [true, false].each do |perform_caching|
          describe "with perform_caching #{ perform_caching }" do
            around do |example|
              previous = ActionController::Base.perform_caching
              ActionController::Base.perform_caching = perform_caching
              example.run
            ensure
              ActionController::Base.perform_caching = previous
            end

            it 'raises for a cache block' do
              expect { render_docx('reports/cache_block') }.to raise_fragment_caching_error('cache')
            end

            it 'raises for cache_if and cache_unless, whatever their condition' do
              expect { render_docx('reports/cache_if') }.to raise_fragment_caching_error('cache_if')
              expect { render_docx('reports/cache_unless') }.to raise_fragment_caching_error('cache_unless')
            end

            it 'raises for a collection rendered with cached: true' do
              expect { render_docx('reports/cached_clients', locals: { clients: clients }) }.to raise_fragment_caching_error('render cached: true')
            end

            it 'raises for a cache block in a partial' do
              expect { render_docx('reports/cache_in_partial') }.to raise_fragment_caching_error('cache')
            end

            it 'raises for a cache block in the block of render(layout:)' do
              expect { render_docx('reports/cache_in_layout_block') }.to raise_fragment_caching_error('cache')
            end

            it 'renders a collection with cached: false' do
              expect(docx_text(render_docx('reports/uncached_clients', locals: { clients: clients }))).to eq "ACME GmbH\nKiel\nBeta AG\nHamburg"
            end
          end
        end

        # The fragment of an ERB partial is its output, so its cache holds
        # the text the view asks for. The second render shows the hit: it
        # holds the name or the year of the first.
        describe 'in an ERB partial rendered from a view, with perform_caching on' do
          around do |example|
            previous = ActionController::Base.perform_caching
            ActionController::Base.perform_caching = true
            example.run
          ensure
            ActionController::Base.perform_caching = previous
          end

          it 'caches a cache block' do
            expect(docx_text(render_docx('reports/with_greeting', locals: { name: 'Anna' }))).to eq 'Hello Anna'
            expect(docx_text(render_docx('reports/with_greeting', locals: { name: 'Ben' }))).to eq 'Hello Anna'
          end

          it 'caches a collection rendered with cached: true' do
            expect(docx_text(render_docx('reports/with_lines', locals: { clients: clients, year: 2025 }))).to eq 'ACME GmbH 2025;Beta AG 2025;'
            expect(docx_text(render_docx('reports/with_lines', locals: { clients: clients, year: 2026 }))).to eq 'ACME GmbH 2025;Beta AG 2025;'
          end
        end

        # ViewComponent keeps a ViewComponent::Template in @current_template
        # while a component renders, an object without a handler.
        it 'passes cache on to Rails where the current template is an object of another library' do
          view = ApplicationController.new.view_context
          view.instance_variable_set(:@current_template, Struct.new(:virtual_path).new('components/card'))

          expect { |block| view.cache('card', skip_digest: true, &block) }.to yield_control
        end

        it 'renders the next view after the error into a document of its own' do
          view = ApplicationController.new.view_context

          expect { view.render(template: 'reports/cache_block', formats: [:docx]) }.to raise_fragment_caching_error('cache')
          expect(docx_text(view.render(template: 'reports/outer', formats: [:docx]))).to eq "Outer\nInner\npartial returned String of 0 bytes"
        end

        it 'leaves fragment caching in views of other formats as it is' do
          perform_caching = ActionController::Base.perform_caching
          ActionController::Base.perform_caching = true
          view = ApplicationController.new.view_context

          expect(view.render(template: 'reports/greeting', formats: [:html], locals: { name: 'Anna' })).to eq 'Hello Anna'
          expect(view.render(template: 'reports/greeting', formats: [:html], locals: { name: 'Ben' })).to eq 'Hello Anna'
        ensure
          ActionController::Base.perform_caching = perform_caching
        end
      end

      # reports/_inner.docx.caracal is the dummy app's.
      describe 'with a layout around a partial or a block' do
        let(:resolver) do
          ActionView::FixtureResolver.new(
            'reports/_box.docx.caracal'        => "docx.p 'Top'\nyield\ndocx.p 'Bottom'",
            'reports/boxed.docx.caracal'       => "render partial: 'reports/inner', layout: 'reports/box'",
            'reports/boxed_block.docx.caracal' => "render(layout: 'reports/box') { docx.p 'Inside' }"
          )
        end

        around do |example|
          view_paths = ApplicationController.view_paths
          ApplicationController.prepend_view_path(resolver)
          example.run
        ensure
          ApplicationController.view_paths = view_paths
        end

        it "adds the commands of a partial's layout behind those of the partial" do
          expect(docx_text(render_docx('reports/boxed'))).to eq "Inner\nTop\nBottom"
        end

        it 'runs a block where its layout yields' do
          expect(docx_text(render_docx('reports/boxed_block'))).to eq "Top\nInside\nBottom"
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