# mos-eisley-lambda

[![Gem Version](https://badge.fury.io/rb/mos-eisley-lambda.svg)](http://badge.fury.io/rb/mos-eisley-lambda) 

“You will never find a more wretched hive of scum and villainy.” – Obi-Wan Kenobi

Episode 2 of the Ruby based [Slack app](https://api.slack.com/) framework, this time for [AWS Lambda](https://aws.amazon.com/lambda/). Pure Ruby, no external gem/library dependency.

## Setup

### AWS

1. Create an IAM role for MosEisley Lambda function
1. Create a Lambda function for MosEisley
   - You can install this gem using [Lambda Layer](#using-with-lambda-layers) or just copy the `lib` directory to your Lambda code.
1. Create an HTTP API Gateway
   1. Create the appropriate routes (or use [the OpenAPI spec](https://github.com/kenjij/mos-eisley-lambda/blob/main/openapi3.yaml))
   1. Create Lambda integration and attach it to all the routes

Configure Lambda environment variable.

- `SLACK_CREDENTIALS_SSMPS_PATH`: hierarchy path to System Managers Parameter Store; e.g., `/slack/credentials/` would reference two parameters:
  - `/slack/credetials/signing_secret`
  - `/slack/credetials/bot_access_token`
- `MOSEISLEY_LOG_LEVEL`: _optional_, could be `DEBUG`, `INFO`, `WARN`, or `ERROR` 
- `SLACK_LOG_CHANNEL_ID`: _optional_, if you want to use `ME::SlackWeb.post_log()`

Configure Lambda code in your `lambda_function.rb` file.

```ruby
require 'mos-eisley-lambda'
# Or, you can just copy the `lib` directory to your Lambda and...
# require_relative './lib/mos-eisley-lambda'

MosEisley::Handler.import
# Or, if you store your handlers in a non-default location, dictate by...
# MosEisley::Handler.import_from_path('./my-handlers')

def lambda_handler(event:, context:)
  MosEisley::lambda_event(event, context)
end
```

### Slack

Create a Slack app and configure the following.

- **Interactivity & Shortcuts** – Request URL should be set to the `/actions` endpoint and Options Load URL should be set to the `/menus` endpoint.
- **Slash Commands** – Request URL should be set to the `/commands` endpoint.
- **OAuth & Permissions** – This is where you get the OAuth Tokens and set Scopes.
- **Event Subscriptions** – Request URL should be set to the `/events` endpoint. You'll likely Subscribe to bot events `app_mention` at a minimum.

### Handlers

Create your own Mos Eisley handlers as blocks and register them. By default, store these Ruby files in the `handlers` directory.

`ME::Handler.command_acks` holds `[Hash<String, Hash>]` which are Slack command keyword and response pair. The response is sent as-is back to Slack as an [immediate response](https://api.slack.com/interactivity/slash-commands#responding_immediate_response).

```ruby
ME::Handler.command_acks.merge!({
  '/command' => {
    response_type: 'in_channel',
    text: '_Working on it…_',
  },
  '/secret' => {
    response_type: 'ephemeral',
    text: '_Just for you…_',
  },
})
```

Add handlers to process the Slack event.

```ruby
ME::Handler.add(:command, 'A Slack command') do |event, myself|
  next unless event[:command] == '/command'
  myself.stop
  txt = "Your wish is my command."
  payload = {
    response_type: 'ephemeral',
    text: txt,
    blocks: [ME::S3PO::BlockKit.sec_text(txt)],
  }
  ME::SlackWeb.post_response_url(event[:response_url], payload)
end
```

### Helpers

- `ME::S3PO` – collection of helpers to analyze/create Slack messages.
- `ME::SlackWeb` – methods for sending payloads to Slack Web API calls.

## Event Lifecycle

### Inbound

1. Slack event is sent to Mos Eisley Lambda function via API Gateway
1. Slack event is verified and produces a parsed object
1. If it's a slash command, MosEisley::Handler.command_acks is referenced and immediate response is sent
1. The original Slack event JSON is sent to the function in a recursive fashion (this is to return the inital response ASAP)

### Event Processing

1. Lambda function is invoked by itself with the original Slack event
1. Handlers are called and processed according to original endpoint the event was sent to; actions, commands, events, menus
1. Send a Slack message as necessary and the Slack event cycle is complete

<!-- ### Outbound, Messaging Only

Invoke the function from another app to send a Slack message

1. Create a Slack message packaged to be sent to the API and invoke the function
1. Message is received, then sent to Slack API according to payload-->

## Using with Lambda Layers

Used the Makefile to create a zip file which can be uploaded to a Lambda Layer.

```sh
make
# Installs the gem to './ruby' then archives it to 'lambda-layers.zip'
```
