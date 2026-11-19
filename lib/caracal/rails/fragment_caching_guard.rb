module Caracal
  module Rails

    # Raised by fragment caching in a .docx.caracal view.
    #
    class FragmentCachingError < StandardError
      def initialize(helper)
        super("#{ helper } in a .docx.caracal view: Rails caches the output of a fragment, and the view's commands " \
              "go to docx, so the cache holds an empty String and a cache hit drops the fragment's content. " \
              "Cache the finished document instead, as \"Long documents and caching\" in the caracal-rails README shows.")
      end
    end

    # Prepended to ActionView::Base. In a .docx.caracal view or partial,
    # cache, cache_if, cache_unless and render with cached: true raise a
    # FragmentCachingError, also with perform_caching off, so the mistake
    # shows on the first render.
    #
    # The guard asks which template is running: @current_template, which
    # Rails sets around every template and which its cache helper reads too.
    # An ERB partial rendered from a .docx.caracal view therefore caches as
    # before, since its fragment is its output, and so do views of other
    # formats. Other libraries keep objects of their own in
    # @current_template (ViewComponent a ViewComponent::Template), so the
    # guard asks for the handler only where there is one.
    #
    module FragmentCachingGuard
      def cache(...)
        _caracal_refuse_fragment_caching 'cache'
        super(...)
      end

      def cache_if(...)
        _caracal_refuse_fragment_caching 'cache_if'
        super(...)
      end

      def cache_unless(...)
        _caracal_refuse_fragment_caching 'cache_unless'
        super(...)
      end

      def render(options = {}, locals = {}, &block)
        _caracal_refuse_fragment_caching 'render cached: true' if options.is_a?(Hash) and options[:cached]
        super
      end

      private

      def _caracal_refuse_fragment_caching(helper)
        template = @current_template
        raise FragmentCachingError, helper if template.respond_to?(:handler) and template.handler == TemplateHandler
      end
    end

  end
end
