class ReportMailer < ApplicationMailer
  def document_ready
    @report = params[:report]
    mail to: params[:recipient], subject: "#{@report.title} is ready"
  end
end
