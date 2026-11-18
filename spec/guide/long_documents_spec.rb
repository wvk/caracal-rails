require 'spec_helper'

# Runs the examples from the README's "Long documents and caching" section:
# spec/dummy/app/controllers/reports_controller.rb,
# spec/dummy/app/jobs/report_document_job.rb and
# spec/dummy/app/mailers/report_mailer.rb.

describe 'Long documents and caching' do
  let!(:report) { Report.create!(title: 'Quarterly Report') }
  let(:docx)    { 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }

  before { Rails.cache.clear }

  def document_xml(docx)
    xml = nil
    Zip::File.open_buffer(StringIO.new(docx)) { |zip| xml = zip.read('word/document.xml') }
    xml.force_encoding(Encoding::UTF_8)
  end

  #--------------------------------------------------------
  # Conditional GET and Rails.cache
  #--------------------------------------------------------

  describe 'ReportsController#show', type: :request do
    before { allow(Caracal::Document).to receive(:render).and_call_original }

    it 'sends the document with an ETag' do
      get "/reports/#{report.id}.docx"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq docx
      expect(response.headers['Content-Disposition']).to include %Q{filename="report-#{report.id}.docx"}
      expect(response.headers['ETag']).to be_present
      expect(document_xml(response.body)).to include 'Quarterly Report', 'Last changed on'
    end

    it 'answers a matching If-None-Match with 304 and renders nothing' do
      get "/reports/#{report.id}.docx"
      etag = response.headers['ETag']

      get "/reports/#{report.id}.docx", headers: { 'If-None-Match' => etag }

      expect(response).to have_http_status(:not_modified)
      expect(Caracal::Document).to have_received(:render).once
    end

    it 'sends the cached bytes and the same ETag on a second request' do
      get "/reports/#{report.id}.docx"
      first_body, first_etag = response.body, response.headers['ETag']

      get "/reports/#{report.id}.docx"

      expect(response.body).to eq first_body
      expect(response.headers['ETag']).to eq first_etag
      expect(Caracal::Document).to have_received(:render).once
    end

    it 'renders again once the record changes' do
      get "/reports/#{report.id}.docx"
      first_etag = response.headers['ETag']

      report.update!(title: 'Annual Report', updated_at: 1.minute.from_now)
      get "/reports/#{report.id}.docx", headers: { 'If-None-Match' => first_etag }

      expect(response).to have_http_status(:ok)
      expect(response.headers['ETag']).not_to eq first_etag
      expect(Caracal::Document).to have_received(:render).twice
    end

    it 'keeps a document and an ETag per locale' do
      get "/reports/#{report.id}.docx"
      english_etag = response.headers['ETag']

      I18n.with_locale(:de) do
        get "/reports/#{report.id}.docx", headers: { 'If-None-Match' => english_etag }
      end

      expect(response).to have_http_status(:ok)
      expect(response.headers['ETag']).not_to eq english_etag
      expect(document_xml(response.body)).to include 'Zuletzt geändert am'
      expect(Caracal::Document).to have_received(:render).twice
    end

    it 'answers If-Modified-Since alone from the time of the record, in any locale' do
      get "/reports/#{report.id}.docx"
      last_modified = response.headers['Last-Modified']

      I18n.with_locale(:de) do
        get "/reports/#{report.id}.docx", headers: { 'If-Modified-Since' => last_modified }
      end

      expect(response).to have_http_status(:not_modified)
    end
  end

  #--------------------------------------------------------
  # Rendering in a job
  #--------------------------------------------------------

  describe ReportDocumentJob, type: :job do
    include ActiveJob::TestHelper

    before { ActionMailer::Base.deliveries.clear }

    it 'attaches the rendered document to the record' do
      ReportDocumentJob.perform_now(report, 'reader@example.com')

      document = report.reload.document
      expect(document).to be_attached
      expect(document.filename.to_s).to eq "report-#{report.id}.docx"
      expect(document.content_type).to eq docx
      expect(document_xml(document.download)).to include 'Quarterly Report'
    end

    it 'mails a link to the document' do
      perform_enqueued_jobs { ReportDocumentJob.perform_later(report, 'reader@example.com') }

      mail = ActionMailer::Base.deliveries.last
      expect(ActionMailer::Base.deliveries.size).to eq 1
      expect(mail.to).to eq ['reader@example.com']
      expect(mail.subject).to eq 'Quarterly Report is ready'
      expect(mail.body.to_s).to include 'http://example.com/rails/active_storage/blobs/redirect/'
    end

    it 'touches the record as it attaches' do
      report.update_columns(updated_at: 2.days.ago)

      expect { ReportDocumentJob.perform_now(report, 'reader@example.com') }
        .to change { report.reload.cache_key_with_version }
    end

    it 'keeps the time of the record when the attach runs in no_touching' do
      report.update_columns(updated_at: 2.days.ago)

      expect {
        Report.no_touching do
          report.document.attach io: StringIO.new('docx'), filename: 'report.docx', content_type: Mime[:docx].to_s
        end
      }.not_to change { report.reload.updated_at }
      expect(report.document).to be_attached
    end
  end
end
