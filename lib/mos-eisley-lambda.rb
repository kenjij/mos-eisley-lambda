require_relative './logger'
require_relative './slack'
require_relative './s3po/s3po'
require_relative './handler'
require 'aws-sdk-sqs'
require 'aws-sdk-ssm'
require 'base64'
require 'json'

ME = MosEisley
SQS = Aws::SQS::Client.new

module MosEisley
  def self.config
    @config ||= {}
  end

  def self.lambda_event(event, context)
    raise 'Pre-flight check failed!' unless preflightcheck
    case
    when event['routeKey']
      # Inbound Slack event (via API GW)
      MosEisley.logger.info('API GW event')
      return apigw_event(event)
    when event.dig('Records',0,'eventSource') == 'aws:sqs'
      # Internal event (via SQS)
      MosEisley.logger.info('SQS event')
      return sqs_event(event)
    else
      # Unknown event
      MosEisley.logger.info('Unknown event')
      return unknown_event(event)
    end
  end

  def self.preflightcheck
    if config[:timestamp]
      MosEisley.logger.debug("Confing already loaded at: #{config[:timestamp]}")
      return true
    end
    env_required = [
      'MOSEISLEY_SQS_URL',
      'SLACK_CREDENTIALS_SSMPS_PATH',
    ]
    env_optional = [
      'MOSEISLEY_LOG_LEVEL',
    ]
    config_required = [
      :signing_secret,
      :bot_access_token,
    ]
    l = ENV['MOSEISLEY_LOG_LEVEL']
    if String === l && ['DEBUG', 'INFO', 'WARN', 'ERROR'].include?(l.upcase)
      MosEisley.logger.level = eval("Logger::#{l.upcase}")
    end
    env_required.each do |v|
      if ENV[v].nil?
        MosEisley.logger.error("Missing environment variable: #{v}")
        return false
      end
      case v
      when 'MOSEISLEY_SQS_URL'
        MosEisley.logger.info("Deprecated environment variable: #{v}")
      when 'SLACK_CREDENTIALS_SSMPS_PATH'
        ssm = Aws::SSM::Client.new
        rparams = {
          path: ENV['SLACK_CREDENTIALS_SSMPS_PATH'],
          with_decryption: true,
        }
        ssm.get_parameters_by_path(rparams).parameters.each do |prm|
          k = prm[:name].split('/').last.to_sym
          config[k] = prm[:value]
          config_required.delete(k)
        end
      end
    end
    unless config_required.empty?
      t = "Missing config values: #{config_required.join(', ')}"
      MosEisley.logger.error(t)
      return false
    end
    config[:timestamp] = Time.now
    MosEisley.logger.info('Config loaded')
    return true
  end

  def self.apigw_event(event)
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
      # Nothing to do, just pass to SQS
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
    m = {
      queue_url: ENV['MOSEISLEY_SQS_URL'],
      message_attributes: {
        'source' => {
          data_type: 'String',
          string_value: 'slack',
        },
        'destination' => {
          data_type: 'String',
          string_value: 'moseisley',
        },
        'endpoint' => {
          data_type: 'String',
          string_value: ep,
        },
      },
      message_body: "{\"payload\":#{se[:json]}}",
    }
    SQS.send_message(m)
    s = m[:message_body].length
    MosEisley.logger.debug("Sent message to SQS with body size #{s}.")
    return resp
  end

  def self.sqs_event(event)
    a = event.dig('Records',0,'messageAttributes')
    src = a.dig('source','stringValue')
    dst = a.dig('destination','stringValue')
    ep = a.dig('endpoint','stringValue')
    se = JSON.parse(event.dig('Records',0,'body'), {symbolize_names: true})
    se = se[:payload]
    MosEisley.logger.debug("Event src: #{src}, dst: #{dst}")
    if src == 'slack'
      # Inbound Slack event
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
    elsif dst == 'slack'
      # An event to be sent to Slack
      MosEisley.logger.debug a.dig('api','stringValue')
    else
      MosEisley.logger.warn('Unknown event, ignored.')
    end
    return 0
  end

  def self.unknown_event(event)
    # TODO hand off to a handler
  end
end
