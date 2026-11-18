class ReportDocumentJob < ApplicationJob
  def perform(report, recipient)
    docx = ReportsController.render :show, formats: [:docx], assigns: { report: report }

    report.document.attach io:           StringIO.new(docx),
                           filename:     "report-#{report.id}.docx",
                           content_type: Mime[:docx].to_s

    ReportMailer.with(report: report, recipient: recipient).document_ready.deliver_later
  end
end
