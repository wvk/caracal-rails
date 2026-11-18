# Sends documents with `render docx:`, as the README's Usage section shows.
# spec/requests/render_docx_spec.rb requests each action.
class MonthlyReportsController < ApplicationController
  before_action { @month = params[:id] }

  def show
    respond_to do |format|
      format.docx { render docx: 'show', filename: "Bericht #{@month}.docx" }
    end
  end

  def preview
    render docx: 'show', disposition: :inline
  end

  def cover
    render docx: 'shared/cover'
  end
end
