# mos-eisley-lambda

[![Gem Version](https://badge.fury.io/rb/mos-eisley-lambda.svg)](http://badge.fury.io/rb/mos-eisley-lambda) 

“You will never find a more wretched hive of scum and villainy.” – Obi-Wan Kenobi

Episode 2 of the Ruby based [Slack app](https://api.slack.com/) framework, this time for [AWS Lambda](https://aws.amazon.com/lambda/). Pure ruby, no external dependency.

## Setup

### AWS

1. Create an SQS queue for MosEisley
1. Create an IAM role for MosEisley Lambda function
1. Create a Lambda function for MosEisley
   - You can install this gem using [Lambda Layer](#using-with-lambda-layers) or just copy the `lib` directory to your Lambda code.
1. Create an HTTP API Gateway
   1. Create the appropriate routes (or use [the OpenAPI spec](https://github.com/kenjij/mos-eisley-lambda/blob/main/openapi3.yaml))
   1. Create Lambda integration and attach it to all the routes

Configure Lambda environment variable.

- `SLACK_SIGNING_SECRET`: your Slack app credentials
- `SLACK_BOT_ACCESS_TOKEN`: your Slack app OAuth token
- `MOSEISLEY_SQS_URL`: AWS SQS URL used for the event pipeline
- `MOSEISLEY_LOG_LEVEL` – optional, could be `DEBUG`, `INFO`, `WARN`, or `ERROR` 

Configure Lambda code in your `lambda_function.rb` file.

```ruby
require 'mos-eisley-lambda'
# Or, you can just copy the `lib` directory to your Lambda and...
# require_relative './lib/mos-eisley-lambda'

MosEisley::Handler.import
# Or, if you store your handlers in a non-default location, dictate by...
# MosEisley::Handler.import_from_path('./my-handlers')

def lambda_handler(event:, context:)
  MosEisley::lambda_event(event)
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

## Protocols

### SQS

- Attributes
  - `source`: `slack`, `moseisley`, or other
    - `endpoint`: if source is `slack`, which endpoint it arrived at
  - `destination`: `slack` or `moseisley`
    - `api`: if destination is `slack`
- Message (JSON)
  - `params`: object, meant to be passed to Slack API 
  - `payload`: the data/payload itself

### Helpers

- `ME::S3PO` – collection of helpers to analyze/create Slack messages.
- `ME::SlackWeb` – methods for sending payloads to Slack Web API calls.

## Event Lifecycle

### Inbound

1. Slack event is sent to Mos Eisley Lambda function via API Gateway
1. Slack event is verified and returned with parsed object
1. If it's a slash command, MosEisley::Handler.command_acks is referenced and immediate response is sent
1. The original Slack event JSON is sent to SQS with attributes

### Event Processing

1. Slack event is recieved by SQS trigger
1. Handlers are called and processed according to original endpoint the event was sent to; actions, commands, events, menus
1. Should send a Slack message to complete the event cycle

<!-- ### Message Publishing

Send a message to SQS from another app to send a Slack message

1. Create a Slack message packaged to be sent to the API and send to SQS
1. Message event is recieved by SQS trigger
1. Message is sent to Slack API -->

## Using with Lambda Layers

Used the Makefile to create a zip file which can be uploaded to a Lambda Layer.

```sh
make
# Installs the gem to './ruby' then archives it to 'lambda-layers.zip'
```
