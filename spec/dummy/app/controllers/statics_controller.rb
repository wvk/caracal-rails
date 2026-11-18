class StaticsController < ApplicationController
  def show
    send_data render_to_string, type: :docx, filename: 'Bericht März.docx'
  end
end
