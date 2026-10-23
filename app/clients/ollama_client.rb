require "net/http"
require "json"

# A local LLM through Ollama (https://ollama.com): free, runs on this machine, no data
# leaves it. Only /api/chat is used, with tool calling.
#
#   OllamaClient.new.chat(messages: [ { role: "user", content: "Olá" } ], tools: [ ... ])
#   # => { "role" => "assistant", "content" => "...", "tool_calls" => [ ... ] }
#
# Set OLLAMA_URL (and optionally OLLAMA_MODEL) to turn it on; in development it is on by
# default at http://localhost:11434. Without it the app keeps its rule-based chat only.
class OllamaClient
  class Error < StandardError; end

  DEFAULT_URL = "http://localhost:11434".freeze
  DEFAULT_MODEL = "qwen2.5:3b".freeze
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 120 # the first answer waits for the model to load

  def self.enabled?
    ENV["OLLAMA_URL"].present? || Rails.env.development?
  end

  def initialize(url: ENV.fetch("OLLAMA_URL", DEFAULT_URL), model: ENV.fetch("OLLAMA_MODEL", DEFAULT_MODEL))
    @uri = URI.join(url, "/api/chat")
    @model = model
  end

  def chat(messages:, tools: [])
    request = Net::HTTP::Post.new(@uri, "Content-Type" => "application/json")
    request.body = JSON.generate(model: @model, messages: messages, tools: tools, stream: false,
                                 options: { temperature: 0.1 })
    response = Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == "https",
                               open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |http| http.request(request) }
    raise Error, "O Ollama respondeu #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("message")
  rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    raise Error, "O Ollama não está disponível (#{e.class.name})"
  rescue JSON::ParserError, KeyError
    raise Error, "Resposta inválida do Ollama"
  end
end
