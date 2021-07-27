Gem::Specification.new do |s|
  s.name          = 'mos-eisley-lambda'
  s.version       = '0.4.1'
  s.authors       = ['Ken J.']
  s.email         = ['kenjij@gmail.com']
  s.summary       = %q{Ruby based Slack bot framework, for AWS Lambda use}
  s.description   = %q{Ruby based Slack bot framework, for AWS Lambda use. Also provides helpers to analyze/build messages. Event based utilizing SQS.}
  s.homepage      = 'https://github.com/kenjij/mos-eisley-lambda'
  s.license       = 'MIT'

  s.files         = `git ls-files`.split($/)
  s.require_paths = ['lib']

  s.required_ruby_version = '>= 2.7'
end
