#
# S3PO - Slack protocol droid in Mos Eisley
#     ::BlockKit - Block Kit tools
#
module MosEisley
  module S3PO
    module BlockKit
      VERSION = '20221028'.freeze

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
      def self.option(value, txt, type = :emoji)
        t = MosEisley::S3PO::BlockKit.text(txt, type)
        {
          text: t,
          value: value,
        }
      end

      # @param values [Array<String>]
      # @param texts [Array<String>]
      # @param type [Symbol] :plain_text | :emoji
      # @return [Hash] Block Kit select menu (static) object
      def self.select_menu(values, texts, type = :emoji)
        # TODO genarate a static select menu block element
        # https://api.slack.com/reference/block-kit/block-elements#static_select
      end
    end
  end
end
