source 'https://rubygems.org'

gemspec

# caracal 2.x is installed from GitHub; rubygems.org carries the 1.x line.
gem 'caracal', github: 'wvk/caracal', branch: 'master'

# lets CI test against specific Rails versions
gem 'rails', ENV['RAILS_VERSION'] if ENV['RAILS_VERSION']
