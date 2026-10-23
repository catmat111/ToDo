# Stands in for OllamaClient: replays canned assistant messages, records what it was sent.
class FakeOllama
  attr_reader :requests

  def initialize(*replies)
    @replies = replies
    @requests = []
  end

  def chat(messages:, tools: [])
    @requests << messages.dup
    @replies.shift || { "role" => "assistant", "content" => "" }
  end

  def self.call_tool(name, arguments)
    { "role" => "assistant", "content" => "", "tool_calls" => [ { "function" => { "name" => name, "arguments" => arguments } } ] }
  end

  def self.say(text)
    { "role" => "assistant", "content" => text }
  end
end
