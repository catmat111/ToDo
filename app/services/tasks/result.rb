module Tasks
  # Outcome of a Tasks service.
  #   result.success?   -> did the flow complete?
  #   result.task       -> the (possibly unsaved) task, with errors when it failed
  #   result.error      -> pt-PT message when it failed
  #   result.next_task  -> next occurrence created when completing a recurring task
  Result = Struct.new(:success, :task, :error, :next_task, keyword_init: true) do
    def success?
      success == true
    end

    def failure?
      !success?
    end
  end
end
