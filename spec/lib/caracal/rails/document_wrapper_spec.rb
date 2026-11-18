require 'spec_helper'

describe Caracal::Rails::DocumentWrapper do

  # Renders a document, handing the block the wrapper around it.
  def render_wrapped(&block)
    Caracal::Document.render {|document| block[described_class.new(document)] }
  end

  # The parts of a rendered document by name, e.g. 'word/styles.xml'.
  def parts(docx)
    parts = {}
    Zip::File.open_buffer(StringIO.new(docx)) do |zip|
      zip.each {|entry| parts[entry.name] = zip.read(entry.name) }
    end
    parts
  end

  def letterhead(docx)
    docx.p 'ACME GmbH', bold: true
  end

  #--------------------------------------------------------
  # Headers and footers
  #--------------------------------------------------------

  describe 'headers and footers' do
    it 'sends the commands of a helper called in a header block to the header' do
      docx = render_wrapped do |docx|
        docx.header {|h| letterhead(docx) }
        docx.p 'Body text'
      end

      expect(docx_text(docx, part: 'word/header1.xml')).to eq 'ACME GmbH'
      expect(docx_text(docx)).to eq 'Body text'
    end

    it 'sends the commands to footers and first-page headers too' do
      docx = render_wrapped do |docx|
        docx.footer {|f| docx.p 'Footer' }
        docx.header(first: true) {|h| docx.p 'First page' }
      end

      expect(docx_text(docx, part: 'word/footer1.xml')).to eq 'Footer'
      expect(docx_text(docx, part: 'word/header2.xml')).to eq 'First page'
      expect(docx_text(docx)).to eq ''
    end

    it 'evaluates a block without a parameter inside the header' do
      docx = render_wrapped do |docx|
        docx.header do
          p 'Own'
          docx.p 'Through docx'
        end
      end

      expect(docx_text(docx, part: 'word/header1.xml')).to eq "Own\nThrough docx"
    end

    it 'sends the commands to the body again after an exception in a header block' do
      docx = render_wrapped do |docx|
        begin
          docx.header do |h|
            docx.p 'Before'
            raise 'stop'
          end
        rescue RuntimeError
        end
        docx.p 'After'
      end

      expect(docx_text(docx, part: 'word/header1.xml')).to eq 'Before'
      expect(docx_text(docx)).to eq 'After'
    end

    it 'returns the header without a block' do
      docx = render_wrapped do |docx|
        expect(docx.header).to be docx.document.headers[:default]
        docx.header.p 'Title'
      end

      expect(docx_text(docx, part: 'word/header1.xml')).to eq 'Title'
    end

    it 'sends settings to the document while a header is open' do
      docx = render_wrapped do |docx|
        docx.header do |h|
          docx.style id: 'Letterhead', name: 'Letterhead', bold: true
          docx.p 'ACME GmbH', style: 'Letterhead'
        end
      end

      expect(parts(docx)['word/styles.xml']).to include 'w:styleId="Letterhead"'
      expect(docx_paragraphs(docx, part: 'word/header1.xml')).to eq [['Letterhead', 'ACME GmbH']]
    end
  end

  #--------------------------------------------------------
  # Frames
  #--------------------------------------------------------

  describe 'frames' do
    it 'sends the commands to the frame while its block runs' do
      docx = render_wrapped do |docx|
        docx.frame(width: 3600, height: 1440, x: 7200, y: 720) {|f| docx.p 'Offer 2026-118' }
        docx.p 'Body text'
      end

      expect(docx_paragraphs(docx)).to eq [
        [nil,      ''],               # the paragraph that anchors the frame
        ['Normal', 'Offer 2026-118'],
        ['Normal', 'Body text']
      ]
    end

    it 'sends the commands meant for a frame inside a header to that frame' do
      docx = render_wrapped do |docx|
        docx.header do |h|
          docx.frame(width: 3600, height: 1440, x: 7200, y: 720) {|f| letterhead(docx) }
          docx.p 'Header text'
        end
      end

      expect(docx_paragraphs(docx, part: 'word/header1.xml')).to eq [[nil, ''], ['Normal', 'ACME GmbH'], ['Normal', 'Header text']]
      expect(docx_text(docx)).to eq ''
    end

    it 'raises a NoMethodError for commands the frame lacks' do
      expect {
        render_wrapped do |docx|
          docx.frame(width: 3600, height: 1440) {|f| docx.page }
        end
      }.to raise_error(NoMethodError) {|error|
        expect(error.name).to eq :page
        expect(error.receiver).to be_a Caracal::Core::Models::FrameModel
      }
    end
  end

  #--------------------------------------------------------
  # Sections
  #--------------------------------------------------------

  describe 'sections' do
    it 'sends the commands of the header: and footer: blocks to their parts' do
      received = nil
      docx = render_wrapped do |docx|
        docx.section(header: ->(h) { letterhead(docx) }, footer: { default: proc { docx.p 'Section footer' } }) do |section|
          received = section
          docx.p 'Section text'
        end
        expect(received).to be docx
      end

      expect(docx_text(docx, part: 'word/header3.xml')).to eq 'ACME GmbH'
      expect(docx_text(docx, part: 'word/footer3.xml')).to eq 'Section footer'
      expect(docx_text(docx)).to eq 'Section text'
    end
  end

  #--------------------------------------------------------
  # Documents without containers
  #--------------------------------------------------------

  describe 'a document without headers, footers or frames' do
    let(:commands) do
      lambda do |docx|
        docx.style id: 'Accent', name: 'Accent', bold: true
        docx.h1 'Title'
        docx.p 'Body text', style: 'Accent'
        docx.ul { li 'One'; li 'Two' }
        docx.table [['A', 'B'], ['C', 'D']], border_size: 4
        docx.page
        docx.p 'After the break'
      end
    end

    it 'renders as it does without the wrapper' do
      expect(parts(render_wrapped(&commands))).to eq parts(Caracal::Document.render(&commands))
    end
  end

  #--------------------------------------------------------
  # Views
  #--------------------------------------------------------

  # The views are in spec/dummy/app/views/offers, letterhead in
  # spec/dummy/app/helpers/offers_helper.rb.
  describe 'in a .docx.caracal view' do
    def render_view(template, **options)
      ApplicationController.render(template: template, formats: [:docx], **options)
    end

    it 'sends the commands of a helper called in a header block to the header' do
      docx = render_view('offers/show')

      expect(docx_text(docx, part: 'word/header1.xml')).to eq 'ACME GmbH'
      expect(docx_text(docx)).to eq 'Body text'
    end

    describe 'with frames' do
      let(:docx) { render_view('offers/framed', locals: { number: '2026-118' }) }

      it 'sends the commands in a frame block to the frame' do
        expect(docx_paragraphs(docx)).to eq [[nil, ''], ['Normal', 'Offer 2026-118'], ['Normal', 'Body text']]
      end

      it 'sends the commands meant for a frame inside a header to that frame' do
        expect(docx_paragraphs(docx, part: 'word/header1.xml')).to eq [[nil, ''], ['Normal', 'ACME GmbH'], ['Normal', 'Header text']]
      end
    end

    it 'sends the commands to the body again after an exception in a header block' do
      docx = render_view('offers/rescued')

      expect(docx_text(docx, part: 'word/header1.xml')).to eq 'ACME GmbH'
      expect(docx_text(docx)).to eq 'Body text'
    end

    it 'renders a view without headers or frames as caracal does' do
      view = Rails.root.join('app/views/statics/show.docx.caracal').to_s

      expect(parts(render_view('statics/show'))).to eq parts(Tilt.new(view).render)
    end
  end

end
