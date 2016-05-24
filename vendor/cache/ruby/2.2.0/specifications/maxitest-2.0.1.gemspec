# -*- encoding: utf-8 -*-
# stub: maxitest 2.0.1 ruby lib

Gem::Specification.new do |s|
  s.name = "maxitest"
  s.version = "2.0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Michael Grosser"]
  s.date = "2016-05-17"
  s.email = "michael@grosser.it"
  s.executables = ["mtest"]
  s.files = ["bin/mtest"]
  s.homepage = "https://github.com/grosser/maxitest"
  s.licenses = ["MIT"]
  s.rubygems_version = "2.4.5.1"
  s.summary = "Minitest + all the features you always wanted"

  s.installed_by_version = "2.4.5.1" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<minitest>, ["< 5.10.0", ">= 5.0.0"])
      s.add_development_dependency(%q<bump>, [">= 0"])
      s.add_development_dependency(%q<rake>, [">= 0"])
      s.add_development_dependency(%q<rspec>, [">= 0"])
      s.add_development_dependency(%q<wwtd>, [">= 0"])
    else
      s.add_dependency(%q<minitest>, ["< 5.10.0", ">= 5.0.0"])
      s.add_dependency(%q<bump>, [">= 0"])
      s.add_dependency(%q<rake>, [">= 0"])
      s.add_dependency(%q<rspec>, [">= 0"])
      s.add_dependency(%q<wwtd>, [">= 0"])
    end
  else
    s.add_dependency(%q<minitest>, ["< 5.10.0", ">= 5.0.0"])
    s.add_dependency(%q<bump>, [">= 0"])
    s.add_dependency(%q<rake>, [">= 0"])
    s.add_dependency(%q<rspec>, [">= 0"])
    s.add_dependency(%q<wwtd>, [">= 0"])
  end
end
