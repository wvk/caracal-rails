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

    # Prepended to ActionView::Base. While a .docx.caracal view renders,
    # cache, cache_if, cache_unless and render with cached: true raise a
    # FragmentCachingError, also with perform_caching off, so the mistake
    # shows on the first render. Views of other formats cache as before.
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
        raise FragmentCachingError, helper if @_caracal_docx
      end
    end

  end
end
