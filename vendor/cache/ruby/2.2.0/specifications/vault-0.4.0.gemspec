# -*- encoding: utf-8 -*-
# stub: vault 0.4.0 ruby lib

Gem::Specification.new do |s|
  s.name = "vault"
  s.version = "0.4.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Seth Vargo"]
  s.bindir = "exe"
  s.date = "2016-03-31"
  s.description = "Vault is a Ruby API client for interacting with a Vault server."
  s.email = ["sethvargo@gmail.com"]
  s.homepage = "https://github.com/hashicorp/vault-ruby"
  s.licenses = ["MPLv2"]
  s.rubygems_version = "2.4.5.1"
  s.summary = "Vault is a Ruby API client for interacting with a Vault server."

  s.installed_by_version = "2.4.5.1" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<bundler>, [">= 0"])
      s.add_development_dependency(%q<pry>, [">= 0"])
      s.add_development_dependency(%q<rake>, ["~> 10.0"])
      s.add_development_dependency(%q<rspec>, ["~> 3.2"])
      s.add_development_dependency(%q<webmock>, ["~> 1.22"])
    else
      s.add_dependency(%q<bundler>, [">= 0"])
      s.add_dependency(%q<pry>, [">= 0"])
      s.add_dependency(%q<rake>, ["~> 10.0"])
      s.add_dependency(%q<rspec>, ["~> 3.2"])
      s.add_dependency(%q<webmock>, ["~> 1.22"])
    end
  else
    s.add_dependency(%q<bundler>, [">= 0"])
    s.add_dependency(%q<pry>, [">= 0"])
    s.add_dependency(%q<rake>, ["~> 10.0"])
    s.add_dependency(%q<rspec>, ["~> 3.2"])
    s.add_dependency(%q<webmock>, ["~> 1.22"])
  end
end
