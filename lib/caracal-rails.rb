require 'caracal'
require 'caracal/rails/document_wrapper'
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

          # A view's digest, which goes into ETags and cache keys, covers the
          # partials that the dependency tracker of its handler finds. Rails'
          # tracker for Ruby code reads the render calls in the code that
          # TemplateHandler.call returns. It is RubyTracker from Rails 7.2 on
          # and RipperTracker in Rails 7.1, which loads the trackers along
          # with ActionView::Digestor.
          require 'action_view/dependency_tracker'
          tracker = ActionView::DependencyTracker.const_defined?(:RubyTracker, false) ? :RubyTracker : :RipperTracker
          ActionView::DependencyTracker.register_tracker :caracal, ActionView::DependencyTracker.const_get(tracker, false)
        end

        # render docx: 'show', filename: 'Bericht März.docx', disposition: :inline
        ActiveSupport.on_load(:action_controller_base) do
          ActionController::Renderers.add :docx do |name, options|
            filename    = options.delete(:filename) || "#{ File.basename(name.to_s) }.docx"
            disposition = (options.delete(:disposition) || :attachment).to_s

            # Rails writes the disposition into the header as it is. Taking the
            # two types alone keeps a value from the request, such as
            # params[:disposition], from adding parameters or lines to it.
            unless %w[attachment inline].include?(disposition.downcase)
              raise ArgumentError, "render docx: takes disposition: :attachment or :inline, got #{ disposition.inspect }"
            end

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
