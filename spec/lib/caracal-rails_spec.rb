require 'spec_helper'

describe Caracal::Rails::Railtie do
    
  #--------------------------------------------------------
  # Tilt Integration
  #--------------------------------------------------------
  
  describe 'tilt integration tests' do
        
    # new
    describe '#new' do
      let(:actual) { Tilt.new("#{ Rails.root }/app/views/statics/show.docx.caracal") }
      
      it { expect(actual).to be_a(Tilt::CaracalTemplate) }
    end
    
    # registration
    describe '#registered?' do
      let(:actual) { Tilt.registered?('caracal') }
      
      it { expect(actual).to eq true }
    end
    
  end
  
  
  #--------------------------------------------------------
  # Mime Type Registration
  #--------------------------------------------------------
  
  describe 'mime type tests' do
     
     # .lookup_by_extension
     describe '#lookup_by_extension' do
       let(:actual) { Mime::Type.lookup_by_extension(:docx) }
       
       it { expect(actual).to be_a(Mime::Type) }
     end
     
  end
  
  
  #--------------------------------------------------------
  # Template Handler Registration
  #--------------------------------------------------------
  
  describe 'template handler tests' do
     
     # .handler_for_extension
     describe '#handler_for_extension' do
       # The railtie registers the handler inside ActiveSupport.on_load(:action_view),
       # which fires when ActionView::Base is first loaded rather than during boot.
       before { ActionView::Base.empty }

       let(:actual) { ActionView::Template.handler_for_extension(:caracal) }

       it { expect(actual).to eq Caracal::Rails::TemplateHandler }
     end
     
  end
  

  #--------------------------------------------------------
  # Dependency Tracker Registration
  #--------------------------------------------------------

  describe 'dependency tracker tests' do
    # The railtie registers the tracker next to the handler.
    before { ActionView::Base.empty }

    # The partials Rails finds in the code of a view named probes/show. The
    # tracker is internal to Rails, so these examples show when a Rails
    # version reads a view differently.
    describe '.find_dependencies' do
      def dependencies(source)
        template = ActionView::Template.new(source, 'probes/show.docx.caracal', Caracal::Rails::TemplateHandler,
                                            locals: [], format: :docx, virtual_path: 'probes/show')
        ActionView::DependencyTracker.find_dependencies('probes/show', template)
      end

      {
        %q{render 'probes/inner'} => %w[probes/inner],
        %q{render 'inner'} => %w[probes/inner],
        %q{result = render(partial: 'probes/inner')} => %w[probes/inner],
        %q{render partial: 'clients/summary', collection: @report.clients, as: :client} => %w[clients/summary],
        %q{render @clients} => %w[clients/client],
        %q{docx.header { |h| render 'offers/letterhead' }} => %w[offers/letterhead],
        %q{docx.frame(width: 3600, height: 1440) { |f| render 'offers/number', number: number }} => %w[offers/number],
        %Q{render partial: "charts/\#{ kind }"\n# Template Dependency: charts/bar\n# Template Dependency: charts/pie} => %w[charts/bar charts/pie],
        %q{docx.h1 'Quarterly Report'} => []
      }.each do |source, expected|
        it "finds #{ expected.inspect } in #{ source.inspect }" do
          expect(dependencies(source)).to eq expected
        end
      end
    end

    # The examples write views into a directory of their own and change a
    # partial. Before each digest they clear Rails' caches of templates and
    # digests, as a deployment does.
    describe 'digest of a view' do
      let(:views) { Pathname(Dir.mktmpdir('views-', Rails.root.join('tmp').tap(&:mkpath).to_s)) }

      after { FileUtils.rm_rf(views) }

      def write(path, source)
        views.join(path).tap {|file| file.dirname.mkpath }.write(source)
      end

      def digest(name)
        ActionView::LookupContext::DetailsKey.clear
        ActionView::Digestor.digest(name: name, format: :docx, finder: ActionView::LookupContext.new([views.to_s], formats: [:docx]))
      end

      it 'changes with a partial the view renders' do
        write 'offers/show.docx.caracal', "docx.h1 'Offer'\nrender 'offers/terms'\n"
        write 'offers/_terms.docx.caracal', "docx.p 'Payable within 30 days'\n"

        expect { write 'offers/_terms.docx.caracal', "docx.p 'Payable within 14 days'\n" }.to change { digest('offers/show') }
      end

      it 'changes with a partial rendered in a header block' do
        write 'offers/show.docx.caracal', "docx.header { |h| render 'offers/letterhead' }\ndocx.p 'Body text'\n"
        write 'offers/_letterhead.docx.caracal', "docx.p 'ACME GmbH'\n"

        expect { write 'offers/_letterhead.docx.caracal', "docx.p 'ACME AG'\n" }.to change { digest('offers/show') }
      end

      it 'changes with a partial of a partial' do
        write 'offers/show.docx.caracal', "render 'offers/letterhead'\ndocx.p 'Body text'\n"
        write 'offers/_letterhead.docx.caracal', "docx.p 'ACME GmbH'\nrender 'offers/address'\n"
        write 'offers/_address.docx.caracal', "docx.p 'Kiel'\n"

        expect { write 'offers/_address.docx.caracal', "docx.p 'Hamburg'\n" }.to change { digest('offers/show') }
      end

      it 'changes with a partial whose name is built at run time and that a comment names' do
        write 'offers/show.docx.caracal', %Q{render partial: "charts/\#{ kind }"\n# Template Dependency: charts/bar\n}
        write 'charts/_bar.docx.caracal', "docx.p 'Bar chart'\n"

        expect { write 'charts/_bar.docx.caracal', "docx.p 'Stacked bar chart'\n" }.to change { digest('offers/show') }
      end

      # Rails looks up each dependency as a partial in the format of the
      # lookup, for ERB views too. The README names the two cases below; an
      # example that fails here shows that a Rails version covers its case.
      it 'stays the same with a template rendered with render template:, also when a comment names it' do
        write 'offers/show.docx.caracal', "docx.h1 'Offer'\nrender template: 'offers/terms'\n# Template Dependency: offers/terms\n"
        write 'offers/terms.docx.caracal', "docx.p 'Payable within 30 days'\n"

        expect { write 'offers/terms.docx.caracal', "docx.p 'Payable within 14 days'\n" }.not_to change { digest('offers/show') }
      end

      it 'stays the same with a partial of another format, also when a comment names it' do
        write 'offers/show.docx.caracal', "docx.p render('offers/terms', formats: [:text])\n# Template Dependency: offers/terms\n"
        write 'offers/_terms.text.erb', "Payable within 30 days\n"

        expect { write 'offers/_terms.text.erb', "Payable within 14 days\n" }.not_to change { digest('offers/show') }
      end
    end
  end
  
end