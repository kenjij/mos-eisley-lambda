module MosEisley
  def self.handlers
    MosEisley::Handler.handlers
  end

  class Handler
    # Import handlers from designated directory
    def self.import
      path = File.expand_path('./handlers')
      import_from_path(path)
    end

    # Import handlers from a directory
    # @param path [String] directory name
    def self.import_from_path(path)
      Dir.chdir(path) {
        Dir.foreach('.') { |f| load f unless File.directory?(f) }
      }
    end

    # Call as often as necessary to add handlers with blocks; each call creates a MosEisley::Handler object
    # @param type [Symbol] :action | :command_response | :command | :event | :menu
    # @param name [String] required for type = :command_response, otherwise optional
    def self.add(type, name = nil, &block)
      if type == :command_response && name.nil?
        raise ArgumentError.new('Name required for :command_response.')
      end
      @handlers ||= {
        action: [],
        command_response: {},
        command: [],
        event: [],
        menu: [],
        nonslack: [],
      }
      h = MosEisley::Handler.new(type, name, &block)
      if type == :command_response
        @handlers[type][name] = h 
      else
        @handlers[type] << h
      end
      MosEisley.logger.debug("Added handler: #{h}")
    end

    # @return [Hash<Symbol, Array>] containing all the handlers
    def self.handlers
      @handlers
    end

    # Run the handlers, typically called by the server
    # @param event [Hash] from Slack Events API JSON data
    def self.run(type, event)
      logger = MosEisley.logger
      response = nil
      if type == :command_response
        h = @handlers[type][event[:command]]
        if h
          response = h.run(event)
          logger.info("Done running #{type} handlers.")
        end
      else
        @handlers[type].each do |h|
          response = h.run(event)
          if h.stopped?
            logger.debug('Handler stop was requested.')
            break
          end
        end
        logger.info("Done running #{type} handlers.")
      end
      response
    end

    attr_reader :type, :name

    def initialize(t, n = nil, &block)
      @type = t
      @name = n
      @block = block
      @stopped = false
    end

    def run(event)
      logger = MosEisley.logger
      logger.warn("No block to execute for #{@type} handler: #{self}") unless @block
      logger.debug("Running #{@type} handler: #{self}")
      @stopped = false
      @block.call(event, self)
    rescue => e
      logger.error(e.message)
      logger.error(e.backtrace.join("\n"))
      {text: "Woops, encountered an error."}
    end

    def stop
      @stopped = true
    end

    def stopped?
      @stopped
    end

    def to_s
      "#<#{self.class}:#{self.object_id.to_s(16)}(#{type}:#{name})>"
    end
  end
end
