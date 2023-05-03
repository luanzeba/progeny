# frozen_string_literal: true

require_relative "lib/progeny/version"

Gem::Specification.new do |spec|
  spec.name = "progeny"
  spec.version = Progeny::VERSION
  spec.authors = ["Luan Vieira"]
  spec.email = ["luanv@me.com"]

  spec.summary = "A popen3 wrapper with a nice interface and extra options."
  spec.description = "Spawn child processes without managing IO streams, zombie processes and other details."
  spec.homepage = "https://github.com/luanzeba/progeny"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage + "/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = %w[lib/progeny.rb lib/progeny/command.rb lib/progeny/version.rb README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ["lib"]

  spec.add_development_dependency 'minitest', '>= 4'
  spec.add_development_dependency 'rake', '~> 13.0'
end
