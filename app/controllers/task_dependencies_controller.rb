# Add / remove "bloqueada por" links on a task (both tasks must be the user's own).
class TaskDependenciesController < ApplicationController
  before_action :set_task

  def create
    blocker = Current.user.tasks.find(params.expect(task_dependency: [ :blocker_id ])[:blocker_id])
    dependency = @task.task_dependencies.build(blocker: blocker)
    if dependency.save
      redirect_to @task, notice: "«#{@task.title}» fica à espera de «#{blocker.title}»."
    else
      redirect_to @task, alert: dependency.errors.full_messages.to_sentence
    end
  end

  def destroy
    @task.task_dependencies.find(params[:id]).destroy!
    redirect_to @task, notice: "Dependência removida.", status: :see_other
  end

  private
    def set_task
      @task = Current.user.tasks.find(params[:task_id])
    end
end
