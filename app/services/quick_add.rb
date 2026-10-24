# The post-it chat outside a task page: one sentence becomes a task — with the date it
# mentions, or for today — or, starting with "evento", a calendar event.
#
#   QuickAdd.call(user, "Ligar ao banco amanhã às 10h") # task due tomorrow 10:00
#   QuickAdd.call(user, "Comprar pão")                  # task for today
#   QuickAdd.call(user, "evento jantar sexta às 20h")   # event Friday 20:00–21:00
#   QuickAdd.call(user, "na etiqueta estudo, angular")  # task in the tag, no date (backlog)
class QuickAdd
  Reply = Data.define(:ok, :text, :record) do
    def ok? = ok
  end

  def self.call(...)
    new(...).call
  end

  def initialize(user, message)
    @user = user
    @raw = message.to_s.strip
  end

  TAGGED = /\A(?:(?:adiciona|adicionar|poe|por|mete|coloca)\s+)?(?:na|a|para a)\s+etiqueta\s+(?:de\s+|do\s+|da\s+)?([^\s,:;]+)\s*[,:;-]\s*(.+)/m

  def call
    if (match = Tasks::Chat.normalize(@raw).match(TAGGED))
      return task(@raw[match.begin(2)..], tag_name: @raw[match.begin(1)...match.end(1)])
    end
    if (match = Tasks::Chat.normalize(@raw).match(/\A(?:novo\s+|marca(?:r)?\s+(?:um\s+)?)?evento\s*:?\s+/))
      event(@raw[match.end(0)..])
    else
      task
    end
  end

  private
    def task(text = @raw, tag_name: nil)
      tag = tag_name && (@user.tags.where("LOWER(name) = ?", tag_name.downcase).first || @user.tags.create(name: tag_name.upcase_first))
      title, found = Tasks::Chat::When.extract(text)
      due = if found.nil? then (tag ? nil : Time.zone.now.end_of_day) # in a tag without a date: backlog
      elsif found.has_time then found.time
      else found.time.end_of_day
      end
      result = Tasks::Create.call(user: @user, params: { title: title.upcase_first, due_at: due, tag_ids: [ tag&.id ].compact })
      return Reply.new(ok: false, text: "Não consegui adicionar: #{result.error.downcase_first}.", record: nil) unless result.success?
      Reply.new(ok: true, text: nil, record: result.task)
    end

    def event(text)
      title, found = Tasks::Chat::When.extract(text)
      unless found
        return Reply.new(ok: false, record: nil, text: "Quando é? Por exemplo: «evento jantar sexta às 20h» ou «evento férias 20/12».")
      end
      event = @user.events.new(title: title, all_day: !found.has_time, starts_at: found.time,
                               ends_at: (found.time + 1.hour if found.has_time))
      return Reply.new(ok: false, text: "Não consegui marcar: #{event.errors.full_messages.to_sentence.downcase_first}.", record: nil) unless event.save
      AuditLog.record("event.created", resource: event, user: @user, title: event.title)
      Reply.new(ok: true, text: nil, record: event)
    end
end
