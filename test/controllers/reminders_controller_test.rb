require "test_helper"

class RemindersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @task = create_task(due_at: 3.days.from_now)
    sign_in_as users(:one)
  end

  test "creates a reminder" do
    at = 1.day.from_now.change(sec: 0)
    assert_difference -> { @task.reminders.count }, 1 do
      post task_reminders_path(@task), params: { reminder: { remind_at: at.strftime("%Y-%m-%dT%H:%M"), channel: "email" } }
    end

    assert_redirected_to task_path(@task)
    assert_match "Lembrete criado", flash[:notice]
    reminder = @task.reminders.last
    assert_equal at, reminder.remind_at
    assert reminder.email?
    assert_equal "reminder.created", AuditLog.last.action
  end

  test "interprets the datetime in the user's time zone" do
    users(:one).update!(timezone: "America/New_York")
    post task_reminders_path(@task), params: { reminder: { remind_at: "2030-06-01T09:00", channel: "in_app" } }

    assert_equal Time.utc(2030, 6, 1, 13, 0), @task.reminders.last.remind_at
  end

  test "creates a reminder from a preset" do
    at = @task.due_at - 1.day
    post task_reminders_path(@task), params: { reminder: { remind_at: at.iso8601, channel: "in_app" } }
    assert_equal at.to_i, @task.reminders.last.remind_at.to_i
  end

  test "rejects a duplicate with a friendly alert" do
    at = 1.day.from_now.change(sec: 0)
    @task.reminders.create!(remind_at: at)

    assert_no_difference -> { Reminder.count } do
      post task_reminders_path(@task), params: { reminder: { remind_at: at.strftime("%Y-%m-%dT%H:%M"), channel: "in_app" } }
    end
    assert_redirected_to task_path(@task)
    assert_equal "Não foi possível criar o lembrete: data do lembrete já tem um lembrete marcado neste canal.", flash[:alert]
  end

  test "rejects an invalid reminder" do
    assert_no_difference -> { Reminder.count } do
      post task_reminders_path(@task), params: { reminder: { remind_at: "", channel: "in_app" } }
    end
    assert_match "data do lembrete tem de ser indicada", flash[:alert]
  end

  test "destroys a reminder" do
    reminder = @task.reminders.create!(remind_at: 1.day.from_now)

    assert_difference -> { Reminder.count }, -1 do
      delete task_reminder_path(@task, reminder)
    end
    assert_redirected_to task_path(@task)
    assert_equal "Lembrete removido.", flash[:notice]
  end

  test "another user cannot add reminders to the task" do
    sign_in_as users(:two)
    assert_no_difference -> { Reminder.count } do
      post task_reminders_path(@task), params: { reminder: { remind_at: 1.day.from_now.iso8601, channel: "in_app" } }
    end
    assert_response :not_found
  end

  test "another user cannot delete reminders of the task" do
    reminder = @task.reminders.create!(remind_at: 1.day.from_now)
    sign_in_as users(:two)

    assert_no_difference -> { Reminder.count } do
      delete task_reminder_path(@task, reminder)
    end
    assert_response :not_found
  end

  test "a reminder cannot be deleted through another task" do
    reminder = @task.reminders.create!(remind_at: 1.day.from_now)
    other_task = create_task

    assert_no_difference -> { Reminder.count } do
      delete task_reminder_path(other_task, reminder)
    end
    assert_response :not_found
  end

  test "section partial lists reminders, presets and the form" do
    @task.update!(due_at: 3.days.from_now.change(hour: 18, min: 0))
    sent = @task.reminders.create!(remind_at: 2.days.from_now, channel: "email")
    sent.update_columns(sent_at: 1.minute.ago)
    @task.reminders.create!(remind_at: 1.day.from_now)

    html = ApplicationController.render(partial: "reminders/section", locals: { task: @task.reload })
    page = Nokogiri::HTML5.fragment(html)

    assert_equal 2, page.css(".reminders__item").size
    assert_equal 1, page.css(".reminders__item--sent").size
    assert page.at_css(".badge--type").text.present?
    assert_includes page.text, "Enviado"
    assert_includes page.text, "Agendado"
    assert page.at_css("form[action='#{task_reminder_path(@task, sent)}'][data-turbo-confirm]")
    assert_includes page.css(".reminders__presets button").map(&:text), "1 dia antes"
    assert page.at_css("input[type='datetime-local'][name='reminder[remind_at]']")
    assert page.at_css("select[name='reminder[channel]'] option[value='email']")
  end

  test "section partial hides the form for closed tasks" do
    @task.update!(status: "cancelled")
    html = ApplicationController.render(partial: "reminders/section", locals: { task: @task })
    assert_includes html, "já não está aberta"
    assert_not_includes html, "Adicionar lembrete"
  end

  test "requires authentication" do
    sign_out
    post task_reminders_path(@task), params: { reminder: { remind_at: 1.day.from_now.iso8601 } }
    assert_redirected_to new_session_path
  end
end
