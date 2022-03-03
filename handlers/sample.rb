##
## Sample handlers for Mos Eisley
##
ME::Handler.add(:event, 'DEBUG') do |event, myself|
  l = ME.logger
  l.debug("[Slack-Event]\n#{event}")
end

ME::Handler.add(:event, 'Request - diagnostics') do |event, myself|
  se = event[:event]
  next unless se[:type] == 'app_mention' && /\bdiag/i =~ se[:text]
  myself.stop
  l = ME.logger
  bk = ME::S3PO::BlockKit
  fs = []
  ME.config.info[:handlers].each{ |k, v| fs << "*#{k}*\n#{v}" }
  blks = [
    bk.sec_text('Handler Count'),
    bk.sec_fields(fs),
  ]
  fs = []
  ME.config.info[:versions].each{ |k, v| fs << "*#{k}*\n#{v}" }
  blks << bk.sec_text('Software Versions')
  blks << bk.sec_fields(fs)
  ME::SlackWeb.chat_postmessage(channel: se[:channel], text: "Diagnostics", blocks: blks)
end

ME::Handler.add(:nonslack, 'DEBUG') do |event, myself|
  l = ME.logger
  l.debug("[Non-Slack]\n#{event}")
end

ME::Handler.add(:command_response, '/sample') do |event, myself|
  {
    response_type: "in_channel",
    text: "_Working on `#{event[:command]}`..._",
  }
end

ME::Handler.add(:command, 'DEBUG') do |event, myself|
  l = ME.logger
  l.debug("[Slack-Command]\n#{event}")
end

ME::Handler.add(:command, 'Request - /sample') do |event, myself|
  next unless event[:command] == '/sample'
  myself.stop
  bk = ME::S3PO::BlockKit
  t = "`S A M P L E` I did it!"
  blks = [
    bk.sec_text(t),
    bk.con_text('By: Mos Eisley sampler'),
  ]
  ME::SlackWeb.chat_postmessage(channel: event[:command], text: t, blocks: blks)
end
