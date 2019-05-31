# frozen_string_literal: true

name = "samson_secret_puller"

Gem::Specification.new name, "1.1.1" do |s|
  s.summary = "Gem to read secrets generated by samson secret puller"
  s.authors = ["Michael Grosser"]
  s.email = "michael@grosser.it"
  s.homepage = "https://github.com/zendesk/#{name}"
  s.files = `git ls-files lib MIT-LICENSE.txt`.split("\n")
  s.license = "MIT"
  s.required_ruby_version = '>= 2.4'
end
