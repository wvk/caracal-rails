require 'spec_helper'

# Requests the actions of spec/dummy/app/controllers/monthly_reports_controller.rb,
# which send documents with `render docx:`.

describe 'render docx:', type: :request do

  # The response is a DOCX named filename, sent with this Content-Disposition
  # and, as send_data sends it, without a charset.
  def expect_docx(filename, content_disposition)
    expect(response).to have_http_status(:ok)
    expect(response).to be_docx.named(filename)
    expect(response.headers['Content-Type']).to eq 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    expect(response.headers['Content-Disposition']).to eq content_disposition
  end

  it 'sends the document under the file name it is given' do
    get '/monthly_reports/Mai.docx'

    expect_docx 'Bericht Mai.docx', %q{attachment; filename="Bericht Mai.docx"; filename*=UTF-8''Bericht%20Mai.docx}
    expect(docx_paragraphs(response.body)).to eq [['Heading1', 'Bericht Mai']]
  end

  it 'adds filename* for a file name outside ASCII' do
    get "/monthly_reports/#{ ERB::Util.url_encode('März') }.docx"

    expect_docx 'Bericht März.docx', %q{attachment; filename="Bericht Marz.docx"; filename*=UTF-8''Bericht%20M%C3%A4rz.docx}
    expect(docx_paragraphs(response.body)).to eq [['Heading1', 'Bericht März']]
  end

  it 'sends the document inline, named after its template' do
    get '/monthly_reports/Mai/preview'

    expect_docx 'show.docx', %q{inline; filename="show.docx"; filename*=UTF-8''show.docx}
    expect(docx_paragraphs(response.body)).to eq [['Heading1', 'Bericht Mai']]
  end

  it 'looks up a name with a slash from the view path and names the file after its last part' do
    get '/monthly_reports/Mai/cover'

    expect_docx 'cover.docx', %q{attachment; filename="cover.docx"; filename*=UTF-8''cover.docx}
    expect(docx_paragraphs(response.body)).to eq [['Heading1', 'Deckblatt Mai']]
  end

end
