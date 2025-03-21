require 'sinatra'
require 'json'
require 'discordrb'
require 'http'
require 'dotenv'
require 'kramdown'
Dotenv.load

# Initialize Discord bot (without running it)

class App < Sinatra::Base
  use Rack::Auth::Basic, "Protected Area" do |username, password|
    username == ENV['HTTP_AUTH_USERNAME'] && password == ENV['HTTP_AUTH_PASSWORD']
  end

  # Fetch last 100 messages from a Discord channel
  def fetch_messages(channel_id)
    bot = Discordrb::Bot.new(token: ENV['BOT_TOKEN'], client_id: ENV['CLIENT_ID'] )
    channel = bot.channel(channel_id)
    return { error: 'Channel not found' } unless channel

    messages = channel.history(100).map do |msg|
      {
        id: msg.id,
        content: msg.content,
        author: msg.author.username,
        timestamp: msg.timestamp
      }
    end

    messages
  rescue StandardError => e
    { error: e.message }
  end

  def prompt_llama(prompt)
    response = HTTP.auth("Bearer #{ENV['REPLICATE_API_TOKEN']}")
                .headers(content_type: 'application/json', prefer: 'wait')
                .post("https://api.replicate.com/v1/models/meta/meta-llama-3.1-405b-instruct/predictions",
                      json: { input: { prompt: prompt} })

    if response.status.success?
      result = response.parse
      if result['output']
        return result['output'].join
      else
        return "Error: No output in response"
      end
    else
      return "Error: #{response.status}"
    end
  end

  # API route to fetch messages from a given channel
  get '/messages/:channel_id' do
    messages = fetch_messages(params[:channel_id].to_i)

    prompt = "
Below are messages from a Discord channel where members of a design studio share links to interesting articles, videos, and other resources. The messages are from the past week.

Your task is to draft a public blog post summarizing the shared content. Follow these guidelines:
* Write the post in Markdown format.
* Each paragraph should summarize one shared link, mentioning:
* * Who shared it
* * A brief summary of the content
* * Any context or commentary they provided
* * A direct link to the resource
* If multiple links relate to a common theme, group them together under a relevant subheading.
* Exclude bot messages, test messages, and unrelated chatter.
* Only output the final blog post content—do not include any additional explanations or preambles.

Here are the messages from the channel:
      "

    params[:days] ||= 7
    one_week_ago = Time.now - (params[:days].to_i * 24 * 60 * 60)
    messages.each do |msg|
      if msg[:timestamp] >= one_week_ago
        prompt << "#{msg[:timestamp]} - #{msg[:author]}: #{msg[:content]}\n"
      end
    end

    markdown_content = prompt_llama(prompt)
    Kramdown::Document.new(markdown_content).to_html
  end

  # Start the Sinatra app
  run! if __FILE__ == $0
end
