#### v2.0.0

* Breaking changes
  * Require caracal 2.0 from [wvk/caracal](https://github.com/wvk/caracal) and Ruby 3.2. caracal 2 is installed from GitHub; rubygems.org carries the 1.x line. (@wvk)
  * Require Rails 7.1, the oldest version CI tests. (@wvk)
  * In a `.docx.caracal` view and its partials, `cache`, `cache_if`, `cache_unless` and `render … cached: true` raise `Caracal::Rails::FragmentCachingError`, also with `perform_caching` off. Rails caches the output of a fragment, which is an empty String in a `.docx.caracal` view, so a cache hit left the fragment's content out of the document without an error. The README's section "Partials and collections" points to "Long documents and caching", which caches the finished document. Views of other formats cache as before. (@wvk)

* Bug Fixes
  * The template handler compiles a view from the source Rails passes it, wrapped in `Caracal::Document.render do |docx|` as `Tilt::CaracalTemplate` wraps it, where it compiled to `Tilt.new(path).render(self)`. Views now read the `locals:` passed to `render` and render from resolvers other than the file system, such as `ActionView::FixtureResolver`. Rails compiles a view once and renders it again without reading its file, where Tilt read and compiled the file on every render. An error on line N of a view reports line N, where Tilt reported N + 1. The template path no longer appears in the generated code. (@wvk)
  * The digest of a view covers the partials it renders, where it covered the view's own file alone. The Railtie registers Rails' dependency tracker for Ruby code, `RubyTracker` (`RipperTracker` in Rails 7.1), for `.caracal` views. After a deployment that changes a partial, `stale?` sets a new ETag, and a cache key built with `ActionView::Digestor` changes. A partial whose name is built at run time goes into the digest through a `# Template Dependency: dir/name` comment. The README's section "Conditional requests and `Rails.cache`" describes what the digest covers. (@wvk)

* Enhancements
  * Continuous integration runs Ruby 3.2 to 4.0 against Rails 7.1 to 8.1. (@wvk)
  * The gem's homepage, source, changelog and issue links point to [wvk/caracal-rails](https://github.com/wvk/caracal-rails). (@wvk)
  * The README's new section "Long documents and caching" renders documents in Active Job into Active Storage, and answers conditional requests and fills `Rails.cache` from a document's inputs. The dummy app now loads Active Record (SQLite in memory), Active Storage, Active Job and Action Mailer, and `spec/guide/long_documents_spec.rb` runs the section's examples. (@wvk)
  * `require 'caracal/rails/test_helpers'` adds test helpers for DOCX responses: the RSpec matcher `be_docx` with `.named(filename)`, the Minitest assertion `assert_docx response, filename:`, and `docx_text` and `docx_paragraphs`, which return the text of a document and its paragraphs with their style ids. They read a file name outside ASCII from `filename*`, and a failure names what they found. The README's new section "Testing" shows them, and the suite's request specs use them. (@wvk)
  * `render docx: 'show', filename: 'Bericht März.docx'` in a controller renders a view and sends it as `send_data` would: with the DOCX `Content-Type` without a charset, and with a `Content-Disposition` header written by `ActionDispatch::Http::ContentDisposition`, so names outside ASCII get `filename*=UTF-8''…`. `filename:` defaults to the template's name with `.docx`, `disposition:` to `:attachment`. The README's controller example uses it in place of a hand-written header. (@wvk)
  * In a view, `docx` sends the commands that add content to the header, footer or frame whose block is running, so a helper that receives `docx` writes into that header, footer or frame, where it wrote into the body. This covers frames inside headers and footers and the `header:` and `footer:` blocks of `docx.section`, and after an error rescued inside a block the commands go to the body again. `docx_text` and `docx_paragraphs` read another part of the package with `part:`, e.g. `part: 'word/header1.xml'`. The README's new section "Headers, footers and frames" describes the behaviour. (@wvk)
  * Partials, collections and templates rendered in a view add to the view's document and return an empty String, where each rendered a document of its own and returned its DOCX. They issue their commands on the view's `docx`, so a partial rendered in a header, footer or frame block adds to that header, footer or frame. A `.docx.caracal` partial rendered outside a `.docx.caracal` view still renders a document of its own. The README's new section "Partials and collections" describes the behaviour. (@wvk)


#### v1.0.3

* Security
  * The template handler no longer interpolates the template path into generated Ruby source. A path containing a single quote closed the string literal, so the remainder was compiled as code by Rails; an ordinary apostrophe in a directory name raised a `SyntaxError` instead. The path is now escaped with `String#inspect`. (@dlauer)

* Bug Fixes
  * Corrected five outdated examples in the README, each confirmed against caracal 1.5.0: `font` and `style` take a hash or block rather than a string, `cell_style` uses `:background` rather than `:background_color`, `br` is not a document level command, and `strong` is not a command at all. (reported by @Alan-M-Thomaz)

* Enhancements
  * Added continuous integration across Ruby 3.1 to 3.4 and Rails 7.1 to 8.1. (@dlauer)
  * Relaxed the bundler development dependency, which made `bundle install` impossible on current bundler, and raised rspec-rails so the suite runs on modern Rails. (@dlauer)
  * Replaced Appraisal, whose configuration referenced a local checkout and covered only Rails 3.2 to 4.1, with a `RAILS_VERSION` environment variable read by the Gemfile. (@dlauer)
  * Raised the rails floor to `>= 6.0`, matching the two argument template handler signature this gem ships. (@dlauer)
  * Modernised the dummy application used by the suite: it now loads only the railties it needs rather than `rails/all`, which required ActiveRecord and sqlite3 for a gem that uses neither. (@dlauer)


#### v1.0.2

* Bug Fixes
  * Added the second parameter to the template handler, which Rails 6 requires. (@emp823)


*Releases before v1.0.2 predate this changelog; see the git history for details.*
