require 'caracal'
require 'caracal/rails/template_handler'
require 'caracal/rails/version'
require 'tilt'
require 'tilt/caracal'


module Caracal
  module Rails
    class Railtie < ::Rails::Railtie
      
      #----------------------------------------------------
      # Register mime types, template handlers and the docx renderer.
      #
      initializer 'caracal.registrations' do
        Tilt.register 'caracal', Tilt::CaracalTemplate

        unless Mime::Type.lookup_by_extension(:docx)
          Mime::Type.register('application/vnd.openxmlformats-officedocument.wordprocessingml.document', :docx)
        end

        ActiveSupport.on_load(:action_view) do
          ActionView::Template.register_template_handler :caracal, Caracal::Rails::TemplateHandler
        end

        # render docx: 'show', filename: 'Bericht März.docx', disposition: :inline
        ActiveSupport.on_load(:action_controller_base) do
          ActionController::Renderers.add :docx do |name, options|
            filename    = options.delete(:filename) || "#{ File.basename(name.to_s) }.docx"
            disposition = options.delete(:disposition) || :attachment

            # Rails before 8.0 has already set :template and :prefixes from the
            # action; render_to_string sets them from name, as render does.
            docx = render_to_string(name, options.except(:template, :prefixes).merge(formats: [:docx]))

            self.content_type = Mime[:docx] unless options[:content_type]
            response.charset  = false
            headers['Content-Disposition'] = ActionDispatch::Http::ContentDisposition.format(disposition: disposition, filename: filename)
            docx
          end
        end
      end
      
    end
  end
end
