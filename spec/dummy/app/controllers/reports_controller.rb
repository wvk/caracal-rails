class ReportsController < ApplicationController
  etag { I18n.locale }

  def show
    @report = Report.find(params[:id])
    return unless stale?(@report)

    docx = Rails.cache.fetch([@report.cache_key_with_version, template_digest, I18n.locale]) do
      render_to_string :show
    end
    send_data docx, type: :docx, filename: "report-#{@report.id}.docx"
  end

  private

  def template_digest
    ActionView::Digestor.digest(name: 'reports/show', format: :docx, finder: lookup_context)
  end
end
