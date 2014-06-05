# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'canis/version'

Gem::Specification.new do |spec|
  spec.name          = "canis"
  spec.version       = Canis::VERSION
  spec.authors       = ["kepler"]
  spec.email         = ["githubkepler.50s@gishpuppy.com"]
  spec.summary       = %q{ruby ncurses library for easy application development}
  spec.description   = %q{ruby ncurses library for easy application development providing most controls, minimal source}
  spec.homepage      = "https://github.com/mare-imbrium/canis"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake", ">= 0.9.6"
  #spec.add_development_dependency "ffi-ncurses", ">= 0.4.0"
  spec.add_runtime_dependency "ffi-ncurses", ">= 0.4.0", ">= 0.4.0"
end
