module JobApplications
  # Outcome of a JobApplications service.
  #   result.success?         -> did the flow complete?
  #   result.job_application  -> the (possibly unsaved) application
  #   result.error            -> pt-PT message when it failed
  #   result.created          -> false when an existing application was returned instead
  #   result.event / tasks    -> records created along the way
  Result = Struct.new(:success, :job_application, :error, :created, :event, :tasks, keyword_init: true) do
    def success?
      success == true
    end

    def failure?
      !success?
    end

    def created?
      created == true
    end

    def tasks
      self[:tasks] || []
    end
  end
end
