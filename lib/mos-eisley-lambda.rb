require_relative './logger'
require_relative './slack'
require_relative './s3po/s3po'
require_relative './handler'
require 'aws-sdk-sqs'
require 'base64'
require 'json'

ME = MosEisley
SQS = Aws::SQS::Client.new

module MosEisley
  def self.lambda_event(event)
    abort unless preflightcheck
    # Inbound Slack event (via API GW)
    if event['routeKey']
      MosEisley.logger.info('API GW event')
      return apigw_event(event)
    end
    # Internal event (via SQS)
    if event.dig('Records',0,'eventSource') == 'aws:sqs'
      MosEisley.logger.info('SQS event')
      return sqs_event(event)
    end
  end

  def self.preflightcheck
    l = ENV['MOSEISLEY_LOG_LEVEL']
    if String === l && ['DEBUG', 'INFO', 'WARN', 'ERROR'].include?(l.upcase)
      MosEisley.logger.level = eval("Logger::#{l.upcase}")
    end
    env_required = [
      'MOSEISLEY_SQS_URL',
      'SLACK_SIGNING_SECRET',
      'SLACK_BOT_ACCESS_TOKEN',
    ]
    env_optional = [
      'MOSEISLEY_LOG_LEVEL',
    ]
    env_required.each do |e|
      if ENV[e].nil?
        MosEisley.logger.error("Missing environment variable: #{e}")
        return false
      end
    end
    return true
  end

  def self.apigw_event(event)
    se = ME::SlackEvent.validate(event)
    unless se[:valid?]
      MosEisley.logger.warn("#{se[:msg]}")
      return {statusCode: 401}
    end
    resp = {statusCode: 200}
    ep = event['routeKey'].split[-1]
    MosEisley.logger.debug("Inbound Slack request to: #{ep}")
    case ep
    when '/actions'
      # Nothing to do, just pass to SQS
    when '/commands'
      ser = {}
      ack = ME::Handler.command_acks[se[:event][:command]]
      if ack
        ser[:response_type] = ack[:response_type]
        ser[:text] =
          if ack[:text]
            ack[:text]
          else
            text = sep[:text].empty? ? '' : " #{se[:event][:text]}"
            "Received: `#{se[:event][:command]}#{text}`"
          end
        # AWS sets status code and headers by passing JSON string
        resp = JSON.fast_generate(ser)
      end
    when '/events'
      # Respond to Slack challenge request
      if se[:event][:url_verification]
        c = se[:event][:challenge]
        MosEisley.logger.info("Slack Events API challenge accepted: #{c}")
        return "{\"challenge\": \"#{c}\"}"
      end
    when '/menus'
      # ME::Handler.run(:menu, se)
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
        ME::Handler.run(:action, se)
      when '/commands'
        ME::Handler.run(:command, se)
      when '/events'
        ME::Handler.run(:event, se)
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
end
