module OffersHelper
  def letterhead(docx)
    docx.p 'ACME GmbH', bold: true
  end
end
