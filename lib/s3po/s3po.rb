require 'json'
require 'time'
require_relative './blockkit'

module MosEisley
  module S3PO
    def self.parse_json(json)
      return JSON.parse(json, {symbolize_names: true})
    rescue => e
      MosEisley.logger.warn("JSON parse error: #{e}")
      return nil
    end

    # Convert object into JSON, optionally pretty-format
    # @param obj [Object] any Ruby object
    # @param opts [Hash] any JSON options
    # @return [String] JSON string
    def self.json_with_object(obj, pretty: false, opts: nil)
      return '{}' if obj.nil?
      if pretty
        opts = {
          indent: '  ',
          space: ' ',
          object_nl: "\n",
          array_nl: "\n"
        }
      end
      JSON.fast_generate(MosEisley::S3PO.format_json_value(obj), opts)
    end

    # Return Ruby object/value to JSON standard format
    # @param val [Object]
    # @return [Object]
    def self.format_json_value(val)
      s3po = MosEisley::S3PO
      case val
      when Array
        val.map { |v| s3po.format_json_value(v) }
      when Hash
        val.reduce({}) { |h, (k, v)| h.merge({k => s3po.format_json_value(v)}) }
      when String
        val.encode('UTF-8', {invalid: :replace, undef: :replace})
      when Time
        val.utc.iso8601
      else
        val
      end
    end

    def self.create_event(e, my_id: nil, type: nil)
      type ||= e[:type] if e[:type]
      case type
      when 'message', 'app_mention'
        return Message.new(e, my_id)
      when :action
        return Action.new(e)
      else
        return GenericEvent.new(e)
      end
    end

    # Escape string with basic Slack rules; no command encoding is done as it often requires more information than provided in the text
    # @param text [String] string to escape
    # @return [String] escaped text
    def self.escape_text(text)
      esced = String.new(text)
      esced.gsub!('&', '&amp;')
      esced.gsub!('<', '&lt;')
      esced.gsub!('>', '&gt;')
      return esced
    end

    # Return plain text parsing Slack escapes and commands
    # @param text [String] string to decode
    # @return [String] plain text
    def self.decode_text(text)
      plain = String.new(text)
      # keep just the labels
      plain.gsub!(/<([#@]*)[^>|]*\|([^>]*)>/, '<\1\2>')
      # process commands
      plain.gsub!(/<!(everyone|channel|here)>/, '<@\1>')
      plain.gsub!(/<!(.*?)>/, '<\1>')
      # remove brackets
      plain.gsub!(/<(.*?)>/, '\1')
      # unescape
      plain.gsub!('&gt;', '>')
      plain.gsub!('&lt;', '<')
      plain.gsub!('&amp;', '&')
      return plain
    end

    # Return text with basic visual formatting symbols removed;
    #   it will remove all symbols regardless of syntax
    # @param text [String] string to clean up
    # @return [String] cleaned text
    def self.remove_symbols(text)
      text.delete('_*~`')
    end

    # Enclose Slack command in control characters
    # @param cmd [String] command
    # @param label [String] optional label
    # @return [String] escaped command
    def self.escape_command(cmd, label = nil)
      "<#{cmd}" + (label ? "|#{label}" : '') + '>'
    end
  end
end
