module JobApplications
  # "Criar tarefa" on an application: a job task linked to it, titled after the current stage
  # ("Candidatar-me: X" while saved, "Preparar entrevista: X" during interviews, …).
  # The user is then sent to the task's edit page to fill in dates and details.
  class CreateTask
    def self.call(...)
      new(...).call
    end

    def initialize(job_application)
      @job_application = job_application
    end

    def call
      task = job_application.user.tasks.new(
        title: job_application.suggested_task_title,
        task_type: "job",
        job_application: job_application
      )

      if task.save
        AuditLog.record("job_application.task_created", resource: job_application, user: job_application.user,
                        task_id: task.id, status: job_application.status)
        Result.new(success: true, job_application: job_application, tasks: [ task ])
      else
        Result.new(success: false, job_application: job_application, tasks: [ task ],
                   error: task.errors.full_messages.to_sentence)
      end
    end

    private
      attr_reader :job_application
  end
end
