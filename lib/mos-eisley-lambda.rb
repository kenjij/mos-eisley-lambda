require_relative './logger'
require_relative './slack'
require_relative './s3po/s3po'
require_relative './handler'
require_relative './version'
require 'aws-sdk-lambda'
require 'aws-sdk-ssm'
require 'base64'
require 'json'

ME = MosEisley

module MosEisley
  def self.config(context = nil, data = nil)
    if data
      unless @config
        @config = Config.new(context, data)
        MosEisley.logger.info('Config loaded')
      else
        MosEisley.logger.warn('Ignored, already configured')
      end
    end
    @config
  end

  def self.lambda_event(event, context)
    raise 'Pre-flight check failed!' unless preflightcheck(context)
    case
    when event['initializeOnly']
      MosEisley.logger.info('Dry run, initializing only')
      return
    when event['routeKey']
      # Inbound Slack event (via API GW)
      MosEisley.logger.info('API GW event')
      return apigw_event(event, context)
    when event.dig('Records',0,'eventSource') == 'MosEisley:Slack_event'
      # Internal event (via invoke)
      MosEisley.logger.info('Invoke event')
      MosEisley.logger.debug("#{event}")
      return invoke_event(event)
    when event.dig('Records',0,'eventSource').start_with?('MosEisley:Slack_message:')
      # Outbound Slack messaging request (via invoke)
      MosEisley.logger.info('Messaging event')
      MosEisley.logger.debug("#{event}")
      return # TODO implement
    else
      # Non-Slack event
      MosEisley.logger.info('Non-Slack event')
      return nonslack_event(event)
    end
  end

  def self.preflightcheck(context)
    if config
      MosEisley.logger.debug("Confing already loaded at: #{config.timestamp}")
      return true
    end
    env_required = [
      'SLACK_CREDENTIALS_SSMPS_PATH',
    ]
    env_optional = [
      'MOSEISLEY_HANDLERS_DIR',
      'MOSEISLEY_LOG_LEVEL',
      'SLACK_LOG_CHANNEL_ID',
    ]
    config_required = [
      :signing_secret,
      :bot_access_token,
    ]
    l = ENV['MOSEISLEY_LOG_LEVEL']
    if String === l && ['DEBUG', 'INFO', 'WARN', 'ERROR'].include?(l.upcase)
      MosEisley.logger.level = eval("Logger::#{l.upcase}")
    end
    if dir = ENV['MOSEISLEY_HANDLERS_DIR']
      MosEisley::Handler.import_from_path(dir)
    else
      MosEisley::Handler.import
    end
    env_required.each do |v|
      if ENV[v].nil?
        MosEisley.logger.error("Missing environment variable: #{v}")
        return false
      end
      case v
      when 'SLACK_CREDENTIALS_SSMPS_PATH'
        ssm = Aws::SSM::Client.new
        rparams = {
          path: ENV['SLACK_CREDENTIALS_SSMPS_PATH'],
          with_decryption: true,
        }
        c = {}
        ssm.get_parameters_by_path(rparams).parameters.each do |prm|
          k = prm[:name].split('/').last.to_sym
          c[k] = prm[:value]
          config_required.delete(k)
        end
        unless config_required.empty?
          t = "Missing config values: #{config_required.join(', ')}"
          MosEisley.logger.error(t)
          return false
        end
        config(context, c)
      end
    end
    return true
  end

  def self.apigw_event(event, context)
    se = MosEisley::SlackEvent.validate(event)
    unless se[:valid?]
      MosEisley.logger.warn("#{se[:msg]}")
      return {statusCode: 401}
    end
    resp = {statusCode: 200}
    ep = event['routeKey'].split[-1]
    MosEisley.logger.debug("Inbound Slack request to: #{ep}")
    case ep
    when '/actions'
      ## Slack Interactivity & Shortcuts
      # Nothing to do, through-pass data
    when '/commands'
      ## Slack Slash Commands
      MosEisley.logger.debug("Slash command event:\n#{se[:event]}")
      r = MosEisley::Handler.run(:command_response, se[:event])
      if String === r
        r = {text: r}
      end
      if Hash === r
        # AWS sets status code and headers by passing JSON string
        resp = JSON.fast_generate(r)
      end
    when '/events'
      ## Slack Event Subscriptions
      # Respond to Slack challenge request
      if se[:event][:type] == 'url_verification'
        c = se[:event][:challenge]
        MosEisley.logger.info("Slack Events API challenge accepted: #{c}")
        return "{\"challenge\": \"#{c}\"}"
      end
    when '/menus'
      # MosEisley::Handler.run(:menu, se)
      # TODO to be implemented
      return "{\"options\": []}"
    else
      MosEisley.logger.warn('Unknown request, ignored.')
      return {statusCode: 400}
    end
    pl = {
      Records: [
        {
          eventSource: 'MosEisley:Slack_event',
          endpoint: ep,
          body: se[:json],
        }
      ]
    }
    lc = Aws::Lambda::Client.new
    params = {
      function_name: context.function_name,
      invocation_type: 'Event',
      payload: JSON.fast_generate(pl),
    }
    r = lc.invoke(params)
    if r.status_code >= 200 && r.status_code < 300
      MosEisley.logger.debug("Successfullly invoked with playload size: #{params[:payload].length}")
    else
      MosEisley.logger.warn("Problem with invoke, status code: #{r.status_code}")
    end
    resp
  end

  def self.invoke_event(event)
    ep = event.dig('Records',0,'endpoint')
    se = JSON.parse(event.dig('Records',0,'body'), {symbolize_names: true})
    case ep
    when '/actions'
      MosEisley::Handler.run(:action, se)
    when '/commands'
      MosEisley::Handler.run(:command, se)
    when '/events'
      MosEisley::Handler.run(:event, se)
    when '/menus'
      MosEisley.logger.warn('Menu request cannot be processed here.')
    else
      MosEisley.logger.warn("Unknown request: #{ep}")
    end
  end

  def self.nonslack_event(event)
    MosEisley::Handler.run(:nonslack, event)
  end

  class Config
    attr_reader :context, :info, :timestamp
    attr_reader :bot_access_token, :signing_secret

    def initialize(context, data)
      data.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
      @context = context
      @info = {
        handlers: {
          action: MosEisley.handlers[:action].length,
          command_response: MosEisley.handlers[:command_response].length,
          command: MosEisley.handlers[:command].length,
          event: MosEisley.handlers[:event].length,
        },
        versions: {
          mos_eisley: MosEisley::VERSION,
          neko_http: Neko::HTTP::VERSION,
          s3po: MosEisley::S3PO::VERSION,
          s3po_blockkit: MosEisley::S3PO::BlockKit::VERSION,
        },
      }
      @timestamp = Time.now
    end

    def arn
      context.invoked_function_arn
    end

    def remaining_time
      context.get_remaining_time_in_millis
    end
  end
end
