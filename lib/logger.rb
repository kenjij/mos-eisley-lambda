require 'logger'

module MosEisley
  def self.logger=(logger)
    @logger = logger
  end

  def self.logger
    @logger ||= Logger.new($stdout, formatter: proc { |s, d, n, m| "#{s} : #{m}\n" })
  end
end
