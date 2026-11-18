# Caracal-Rails

[Caracal](https://github.com/wvk/caracal) is a ruby library for dynamically creating professional-quality Microsoft Word documents.

Caracal-Rails is a drop in solution for registering the Microsoft Word mime type and for establishing a template handler in Rails for the :docx format.  All caracal documents are rendered with an explicit block passing a reference to the Caracal::Document object named `docx`.

Please see the [caracal-example](https://github.com/urvin-compliance/caracal-example) repository for
a working demonstration of the library's capabilities.

## Installation

Caracal-Rails needs Ruby 3.2 or later and caracal 2, which is installed from GitHub. Add both to your application's Gemfile:

    gem 'caracal', github: 'wvk/caracal', tag: 'v2.0.0'
    gem 'caracal-rails', github: 'wvk/caracal-rails'

Then execute:

    $ bundle install


## Usage

Design your controller normally and respond to the `docx` format:

    class ReportsController < ApplicationController
      def show
        # collect your models/view models here

        respond_to do |format|
          format.docx { headers["Content-Disposition"] = "attachment; filename=\"caracal.docx\"" }
        end
      end
    end

Then add a view file with the Caracal extension:

    apps/views/reports/show.docx.caracal

Specify the format `docx` in your route:

    resources :reports, only: [:show], format: 'docx'

Inside your view, simply issue Caracal commands on the document object:

    docx.font name: 'Droid Serif'

    docx.style do
      id     'special'
      name   'Special'
      font   'Droid Serif'
      italic true
      size   16
    end

    docx.h1 'Quarterly Report'
    docx.hr
    @report.clients.each do |client|
      docx.h2 client.name
      docx.p  'Lorem ipsum dolor...'
      docx.p do
        text 'This is a sentence with a '
        link 'link', 'http://www.google.com/', style: 'special'
        text ' in the middle.'
      end
      docx.img image_url('https://www.example.com/logo.png'), width: 300, height: 200, align: 'right'
      docx.table client.tablular_data, border_size: 4 do
        cell_style  rows[0], background: '3366cc', color: 'ffffff', bold: true
      end
      docx.page
      docx.p 'This is an bulleted list.'
      docx.ul do
        li do
          text 'Item 1', bold: true
          text ' More text'
        end
        li 'Item 2'
      end
    end


*See the [Caracal](https://github.com/wvk/caracal) library for more details.*  


## Long documents and caching

A view renders inside the request, so a document with many pages or images holds a server thread for the seconds it takes. The bytes also differ between renders of the same input, because every ZIP entry in the package carries the time of its render. An ETag computed from the body, such as the one `Rack::ETag` adds, therefore changes on every request.

The examples below render in a job, and answer conditional requests and fill `Rails.cache` from the inputs of a document. They live in the dummy app in `spec/dummy`, and `spec/guide/long_documents_spec.rb` runs them.

### Rendering in a job

A job renders the view, keeps the result as an Active Storage attachment and mails the reader a link:

    class Report < ApplicationRecord
      has_one_attached :document
    end

    class ReportDocumentJob < ApplicationJob
      def perform(report, recipient)
        docx = ReportsController.render :show, formats: [:docx], assigns: { report: report }

        report.document.attach io:           StringIO.new(docx),
                               filename:     "report-#{report.id}.docx",
                               content_type: Mime[:docx].to_s

        ReportMailer.with(report: report, recipient: recipient).document_ready.deliver_later
      end
    end

    class ReportMailer < ApplicationMailer
      def document_ready
        @report = params[:report]
        mail to: params[:recipient], subject: "#{@report.title} is ready"
      end
    end

with the mail's text in `app/views/report_mailer/document_ready.text.erb`:

    <%= @report.title %> is ready for download:

    <%= rails_blob_url @report.document, disposition: 'attachment' %>

A controller action starts it with `ReportDocumentJob.perform_later(@report, recipient)` and answers at once.

- `ReportsController.render` renders `reports/show.docx.caracal` outside a request. `assigns:` sets the instance variables the view reads, here `@report`. URL helpers in the view take their host from `Rails.application.routes.default_url_options`.
- The blob URL opens the document for anyone who holds the link. For a document that needs an access check, mail a link to your own action, which checks access and then redirects to the blob.
- A page that waits for the document can receive the link from the job as a Turbo Stream instead of a mail: `Turbo::StreamsChannel.broadcast_replace_to` from turbo-rails replaces a "being prepared" notice.

### Conditional requests and `Rails.cache`

A document served directly gets its ETag and its cache key from what goes into it, rather than from its bytes:

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

- `stale?(@report)` sets ETag and Last-Modified from the record, and Rails adds a digest of the action's template to the ETag. A client that holds the current document receives `304 Not Modified`, and nothing renders.
- `Rails.cache` keeps the bytes under the record's `cache_key_with_version`, the template's digest (the same `ActionView::Digestor` call Rails makes for the ETag) and everything else the view reads. Here that is the locale: the view translates its text with `t`. `etag { I18n.locale }` adds the locale to every ETag of the controller as well, so the ETag and the cache key change together.
- A changed record or template gives a new key, and the old entry leaves the cache under the store's expiry policy. Documents of several megabytes need a cache store that holds entries of that size; Memcached's default item limit is 1 MB.

[caracal-md](https://github.com/wvk/caracal-md) runs an external program for each diagram block it renders. Keeping those results in `Rails.cache` across renders is the subject of [#5](https://github.com/wvk/caracal-rails/issues/5) and [wvk/caracal-md#11](https://github.com/wvk/caracal-md/issues/11).


## Contributing

1. Fork it ( https://github.com/wvk/caracal-rails/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request


## Why is It Called Caracal?

Because my son likes caracals. :)


## Inspiration

A tip of the hat to the wonderful PDF generation libraries [Prawn](https://github.com/prawnpdf/prawn) and [Prawnto](https://github.com/GetJobber/prawnto).


## License

Copyright (c) 2014 Urvin LLC

[MIT License](https://github.com/wvk/caracal-rails/blob/master/LICENSE.txt)
