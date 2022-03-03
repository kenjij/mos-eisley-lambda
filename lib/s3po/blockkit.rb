#
# S3PO - Slack protocol droid in Mos Eisley
#     ::BlockKit - Block Kit tools
#
module MosEisley
  module S3PO
    module BlockKit
      VERSION = '20220224'.freeze

      # @param txt [String]
      # @param type [Symbol] :plain | :emoji | :mrkdwn
      # @return [Hash] Block Kit section object
      def self.con_text(txt, type = :mrkdwn)
        {
          type: :context,
          elements: [
            text(txt, type),
          ]
        }
      end

      # @param txt [String]
      # @return [Hash] Block Kit header object
      def self.header(txt)
        {
          type: :header,
          text: text(txt, :emoji),
        }
      end

      # @param txt [String]
      # @param type [Symbol] :plain | :emoji | :mrkdwn
      # @return [Hash] Block Kit section object
      def self.sec_text(txt, type = :mrkdwn)
        {
          type: :section,
          text: text(txt, type),
        }
      end

      # @param fields [Array<String>]
      # @param type [Symbol] :plain | :emoji | :mrkdwn
      # @return [Hash] Block Kit section object
      def self.sec_fields(fields, type = :mrkdwn)
        {
          type: :section,
          fields: fields.map{ |txt| text(txt, type) },
        }
      end

      # @param txt [String]
      # @param type [Symbol] :plain | :emoji | :mrkdwn
      # @return [Hash] Block Kit text object
      def self.text(txt, type = :mrkdwn)
        obj = {text: txt}
        case type
        when :mrkdwn
          obj[:type] = type
        when :emoji
          obj[:emoji] = true
        else
          obj[:emoji] = false
        end
        obj[:type] ||= :plain_text
        obj
      end

      # @param txt [String]
      # @return [Hash] Block Kit plain_text object with emoji:false
      def self.plain_text(txt)
        text(txt, :plain)
      end

      # @param txt [String]
      # @return [Hash] Block Kit plain_text object with emoji:true
      def self.emoji_text(txt)
        text(txt, :emoji)
      end

      # @param value [String] string that will be passed to the app when selected
      # @param txt [String]
      # @param type [Symbol] :plain_text | :emoji | :mrkdwn
      # @return [Hash] Block Kit option object
      def self.option(value, txt, type = :mrkdwn)
        t = MosEisley::S3PO::BlockKit.text(txt, type)
        {
          text: t,
          value: value,
        }
      end
    end
  end
end
