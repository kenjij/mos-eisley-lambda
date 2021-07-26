require 'openssl'
require 'time'
require_relative './neko-http'

module MosEisley
  module SlackEvent
    # Validate incoming Slack request, decodes the body then into JSON
    # @param e [Hash] original AWS API GW event object
    # @return [Hash] {valid?: [Bool], msg: [String], json: [String], event: [Hash]}
    def self.validate(e)
      t = e.dig('headers', 'x-slack-request-timestamp')
      return {valid?: false, msg: 'Invalid request.'} if t.nil?
      if (Time.new - Time.at(t.to_i)).abs > 300
        return {valid?: false, msg: 'Request too old.'}
      end
      b = e['isBase64Encoded'] ? Base64.decode64(e['body']) : e['body']
      s = "v0:#{t}:#{b}"
      k = ENV['SLACK_SIGNING_SECRET']
      sig = "v0=#{OpenSSL::HMAC.hexdigest('sha256', k, s)}"
      if e.dig('headers', 'x-slack-signature') != sig
        return {valid?: false, msg: 'Invalid signature.'}
      end
      b = SlackEvent.parse_http_body(b, e.dig('headers', 'content-type'))
      h = JSON.parse(b, {symbolize_names: true})
      {valid?: true, msg: 'Validated.', json: b, event: h}
    end

    def self.parse_http_body(b, t)
      case t
      when 'application/json'
        b
      when 'application/x-www-form-urlencoded'
        JSON.fast_generate(URI.decode_www_form(b).to_h)
      when 'application/xml'
        require 'rexml/document'
        REXML::Document.new(b)
      else
        b
      end
    end
  end

  module SlackWeb
    BASE_URL = 'https://slack.com/api/'.freeze

    def self.chat_memessage(channel:, text:)
      data = {channel: channel, text: text}
      post_to_slack('chat.meMessage', data)
    end

    def self.chat_postephemeral()
    end

    def self.chat_postmessage(channel:, blocks: nil, text: nil, thread_ts: nil)
      data = {channel: channel}
      if blocks
        data[:blocks] = blocks
        data[:text] = text if text
      else
        text ? data[:text] = text : raise
      end
      data[:thread_ts] = thread_ts if thread_ts
      post_to_slack('chat.postMessage', data)
    end

    def self.chat_schedulemessage()
    end

    def self.post_response_url(url, payload)
      post_to_slack(nil, payload, url)
    end

    def self.post_log(blocks: nil, text: nil)
      if c = ENV['SLACK_LOG_CHANNEL_ID']
        d = {channel: c}
        if blocks
          d[:blocks] = blocks
          if text
            d[:text] = text
          end
        else
          if text
            d[:text] = text
          else
            return nil
          end
        end
        chat_postmessage(d)
      else
        return nil
      end
    end

    def self.views_open(trigger_id:, view:)
      data = {
        trigger_id: trigger_id,
        view: view,
      }
      post_to_slack('views.open', data)
    end

    def self.views_update(view_id:, view:, hash: nil)
      data = {
        view_id: view_id,
        view: view,
      }
      data[:hash] if hash
      post_to_slack('views.update', data)
    end

    def self.views_push(trigger_id:, view:)
    end

    # def self.auth_test
    #   post_to_slack('auth.test')
    # end

    private

    def self.post_to_slack(method, data, url = nil)
      l = MosEisley.logger
      url ||= BASE_URL + method
      head = {authorization: "Bearer #{ENV['SLACK_BOT_ACCESS_TOKEN']}"}
      r = Neko::HTTP.post_json(url, data, head)
      if r[:code] != 200
        l.warn("post_to_slack HTTP failed: #{r[:message]}")
        return nil
      end
      begin
        h = JSON.parse(r[:body], {symbolize_names: true})
        if h[:ok]
          return h
        else
          l.warn("post_to_slack Slack failed: #{h[:error]}")
          l.debug("#{h[:response_metadata]}")
          return nil
        end
      rescue
        return {body: r[:body]}
      end
    end
  end
end
