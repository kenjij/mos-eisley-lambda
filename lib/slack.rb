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

    def self.chat_postephemeral(channel:, blocks: nil, text: nil, thread_ts: nil)
      chat_send(:postEphemeral, channel, blocks, text, thread_ts)
    end

    def self.chat_postmessage(channel:, blocks: nil, text: nil, thread_ts: nil)
      chat_send(:postMessage, channel, blocks, text, thread_ts)
    end

    def self.chat_schedulemessage(channel:, post_at:, blocks: nil, text: nil, thread_ts: nil)
      chat_send(:scheduleMessage, channel, blocks, text, thread_ts, post_at)
    end

    def self.chat_send(m, channel, blocks, text, thread_ts, post_at = nil)
      data = {channel: channel}
      if m == :scheduleMessage
        post_at ? data[:post_at] = post_at : raise
      end
      if blocks
        data[:blocks] = blocks
        data[:text] = text if text
      else
        text ? data[:text] = text : raise
      end
      data[:thread_ts] = thread_ts if thread_ts
      post_to_slack("chat.#{m}", data)
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

    def self.conversations_members(channel:, cursor: nil, limit: nil)
      params = {channel: channel}
      params[:cursor] = cursor if cursor
      params[:limit] = limit if limit
      get_from_slack('conversations.members', params)
    end

    def self.users_info(user)
      get_from_slack('users.info', {user: user})
    end

    def self.users_list(cursor: nil, limit: nil)
      params = {include_locale: true}
      params[:cursor] = cursor if cursor
      params[:limit] = limit if limit
      get_from_slack('users.list', params)
    end

    def self.users_lookupbyemail(email)
      get_from_slack('users.lookupByEmail', {email: email})
    end

    def self.users_profile_get(user)
      get_from_slack('users.profile.get', {user: user})
    end

    def self.auth_test
      post_to_slack('auth.test', '')
    end

    private

    def self.get_from_slack(m, params)
      l = MosEisley.logger
      url ||= BASE_URL + m
      head = {authorization: "Bearer #{ENV['SLACK_BOT_ACCESS_TOKEN']}"}
      r = Neko::HTTP.get(url, params, head)
      if r[:code] != 200
        l.warn("#{m} HTTP failed: #{r[:message]}")
        return nil
      end
      begin
        h = JSON.parse(r[:body], {symbolize_names: true})
        if h[:ok]
          return h
        else
          l.warn("#{m} Slack failed: #{h[:error]}")
          l.debug("#{h[:response_metadata]}")
          return nil
        end
      rescue
        return {body: r[:body]}
      end
    end

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
