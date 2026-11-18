require 'spec_helper'

# spec_helper.rb requires caracal/rails/test_helpers. The examples marked
# "(README)" are those of the README's "Testing" section.

describe Caracal::Rails::TestHelpers, type: :request do
  let!(:report) { Report.create!(title: 'Quarterly Report') }
  let(:docx)    { Caracal::Document.render { |docx| docx.p 'Text' } }

  # A response the dummy app doesn't send.
  def response_with(body, headers = {})
    headers = { 'Content-Type' => Caracal::Rails::DocxReader::MEDIA_TYPE }.merge(headers)
    ActionDispatch::TestResponse.create(200, headers, [body])
  end

  def fail_with(message)
    raise_error(RSpec::Expectations::ExpectationNotMetError, message)
  end

  it 'is included in RSpec example groups and in ActiveSupport::TestCase' do
    expect(self).to be_a described_class
    expect(ActionDispatch::IntegrationTest).to include described_class
  end

  #--------------------------------------------------------
  # be_docx
  #--------------------------------------------------------

  describe '#be_docx' do
    it 'checks a DOCX response and its file name (README)' do
      get "/reports/#{report.id}.docx"

      expect(response).to be_docx.named("report-#{report.id}.docx")
      expect(docx_paragraphs(response.body)).to include ['Heading1', 'Quarterly Report']
      expect(docx_text(response.body)).to include 'Last changed on'
    end

    it 'reads a file name outside ASCII from filename*' do
      get '/statics/show.docx'

      expect(response.headers['Content-Disposition']).to eq %q{attachment; filename="Bericht Marz.docx"; filename*=UTF-8''Bericht%20M%C3%A4rz.docx}
      expect(response).to be_docx.named('Bericht März.docx')
    end

    it 'reads a quoted filename and a bare one' do
      expect(response_with(docx, 'Content-Disposition' => %q{attachment; filename="Say \"Hi\".docx"})).to be_docx.named('Say "Hi".docx')
      expect(response_with(docx, 'Content-Disposition' => 'attachment; filename=report.docx')).to be_docx.named('report.docx')
    end

    it 'reads text inside a quoted string as part of its parameter' do
      expect(response_with(docx, 'Content-Disposition' => %q{attachment; filename="a; filename*=UTF-8''b.docx"})).to be_docx.named(%q{a; filename*=UTF-8''b.docx})
      expect(response_with(docx, 'Content-Disposition' => %q{attachment; title="a; filename=b.docx"; filename=c.docx})).to be_docx.named('c.docx')
    end

    it 'passes for a response without a file name, and for a String' do
      expect(response_with(docx)).to be_docx
      expect(docx).to be_docx
    end

    it 'says which file name it found' do
      get "/reports/#{report.id}.docx"

      expect { expect(response).to be_docx.named('report.docx') }.to fail_with \
        %Q{expected a DOCX named "report.docx", but the file name is "report-#{report.id}.docx" } +
        %Q{(Content-Disposition: attachment; filename="report-#{report.id}.docx"; filename*=UTF-8''report-#{report.id}.docx)}
    end

    it 'says which media type it found' do
      response = response_with('<!DOCTYPE html>', 'Content-Type' => 'text/html; charset=utf-8')

      expect { expect(response).to be_docx }.to fail_with 'expected a DOCX, but the media type is "text/html"'
    end

    it 'says what the body holds when it is no DOCX package' do
      zip = Zip::OutputStream.write_buffer { |out| out.put_next_entry('xl/workbook.xml') }.string

      expect { expect(response_with('<!DOCTYPE html>')).to be_docx }.to fail_with 'expected a DOCX, but the body is not a ZIP archive and starts with "<!DOCTYPE html>"'
      expect { expect(response_with(zip)).to be_docx }.to fail_with 'expected a DOCX, but the body is a ZIP archive without word/document.xml: xl/workbook.xml'
      expect { expect('').to be_docx }.to fail_with 'expected a DOCX, but the body is empty'
    end

    it 'says where it found no file name' do
      expect { expect(response_with(docx)).to be_docx.named('a.docx') }.to fail_with 'expected a DOCX named "a.docx", but the response has no Content-Disposition header'
      expect { expect(response_with(docx, 'Content-Disposition' => 'inline')).to be_docx.named('a.docx') }.to fail_with 'expected a DOCX named "a.docx", but the Content-Disposition names no file: inline'
      expect { expect(docx).to be_docx.named('a.docx') }.to fail_with 'expected a DOCX named "a.docx", but got a String, which carries no file name'
    end

    it 'says that a filename* cannot be decoded' do
      expect { expect(response_with(docx, 'Content-Disposition' => %q{attachment; filename*=latin9''a.docx})).to be_docx.named('a.docx') }.to fail_with \
        %q{expected a DOCX named "a.docx", but the filename* of the Content-Disposition cannot be decoded (unknown encoding name - latin9): attachment; filename*=latin9''a.docx}
      expect { expect(response_with(docx, 'Content-Disposition' => %q{attachment; filename*=UTF-8''%ZZ.docx})).to be_docx.named('a.docx') }.to fail_with \
        %q{expected a DOCX named "a.docx", but the filename* of the Content-Disposition cannot be decoded (invalid %-encoding (%ZZ.docx)): attachment; filename*=UTF-8''%ZZ.docx}
    end

    it 'says what it got in place of a response or a String' do
      expect { expect(nil).to be_docx }.to fail_with 'expected a DOCX, but got nil; the helpers read a response or a String'
      expect { expect(report.document).to be_docx }.to fail_with 'expected a DOCX, but got an instance of ActiveStorage::Attached::One; the helpers read a response or a String'
    end

    it 'fails a 304 response' do
      get "/reports/#{report.id}.docx"
      get "/reports/#{report.id}.docx", headers: { 'If-None-Match' => response.headers['ETag'] }

      expect(response).to have_http_status(:not_modified)
      expect { expect(response).to be_docx }.to fail_with 'expected a DOCX, but the media type is nil'
    end

    it 'negates' do
      expect { expect(docx).not_to be_docx }.to fail_with 'did not expect a DOCX'
      expect(be_docx.named('a.docx').description).to eq 'be a DOCX named "a.docx"'
    end
  end

  #--------------------------------------------------------
  # assert_docx
  #--------------------------------------------------------

  describe '#assert_docx' do
    include Minitest::Assertions

    attr_writer :assertions

    def assertions
      @assertions ||= 0
    end

    it 'checks a DOCX response and its file name (README)' do
      get "/reports/#{report.id}.docx"

      assert_docx response, filename: "report-#{report.id}.docx"
      assert_includes docx_text(response.body), 'Quarterly Report'
    end

    it 'reads a file name outside ASCII' do
      get '/statics/show.docx'

      assert_docx response, filename: 'Bericht März.docx'
    end

    it 'checks a String, as one assertion' do
      expect { assert_docx docx }.to change { assertions }.by(1)
    end

    it 'fails with what it found' do
      get '/statics/show.docx'

      expect { assert_docx response, filename: 'Bericht Marz.docx' }.to raise_error Minitest::Assertion,
        %q{expected a DOCX named "Bericht Marz.docx", but the file name is "Bericht März.docx" } +
        %q{(Content-Disposition: attachment; filename="Bericht Marz.docx"; filename*=UTF-8''Bericht%20M%C3%A4rz.docx)}
      expect { assert_docx response_with('') }.to raise_error Minitest::Assertion, 'expected a DOCX, but the body is empty'
    end
  end

  #--------------------------------------------------------
  # docx_paragraphs and docx_text
  #--------------------------------------------------------

  describe '#docx_paragraphs and #docx_text' do
    let(:docx) do
      Caracal::Document.render do |docx|
        docx.h1 'Clients'
        docx.p do
          text 'ACME GmbH'
          br
          text 'Web:', end_tab: true
          link 'acme.example', 'https://acme.example/'
        end
        docx.table [['Name', 'City']]
        docx.page
        docx.frame width: 2000, height: 1000 do |frame|
          frame.p 'In a frame'
        end
      end
    end

    it 'read a response' do
      get '/statics/show.docx'

      expect(docx_paragraphs(response)).to eq [['Heading1', 'Bericht März'], ['Normal', 'Umsätze im März']]
      expect(docx_text(response)).to eq "Bericht März\nUmsätze im März"
    end

    it 'read paragraphs with their own text, table cells and frames included' do
      expect(docx_paragraphs(docx)).to eq [
        ['Heading1', 'Clients'],
        ['Normal',   "ACME GmbH\nWeb:\tacme.example"],
        ['Normal',   'Name'],
        ['Normal',   'City'],
        [nil,        ''],             # the page break
        [nil,        ''],             # the paragraph that anchors the frame
        ['Normal',   'In a frame']
      ]
      expect(docx_text(docx)).to eq "Clients\nACME GmbH\nWeb:\tacme.example\nName\nCity\n\n\nIn a frame"
    end

    it 'read another part with part:' do
      docx = Caracal::Document.render do |docx|
        docx.header { |header| header.p 'ACME GmbH' }
        docx.p 'Body text'
      end

      expect(docx_paragraphs(docx, part: 'word/header1.xml')).to eq [['Normal', 'ACME GmbH']]
      expect(docx_text(docx, part: 'word/header1.xml')).to eq 'ACME GmbH'
      expect { docx_text(docx, part: 'word/footer1.xml') }.to raise_error ArgumentError, %r{\Athe DOCX has no word/footer1.xml, only _rels/.rels, }
    end

    it 'raise for what is no DOCX' do
      expect { docx_text('<!DOCTYPE html>') }.to raise_error ArgumentError, 'expected a DOCX, but the body is not a ZIP archive and starts with "<!DOCTYPE html>"'
      expect { docx_text(Mail.new.tap { |mail| mail.add_file filename: 'a.docx', content: docx }.attachments.first) }.to raise_error ArgumentError,
        'expected a DOCX, but got an instance of Mail::Part; the helpers read a response or a String'
    end
  end
end
