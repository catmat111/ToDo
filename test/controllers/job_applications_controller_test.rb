require "test_helper"

class JobApplicationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @application = create_job_application(@user, title: "Programador Rails", company_name: "Alfa")
    @application.job_application_events.create!(event_type: "saved", occurred_at: 1.day.ago, notes: "Vi no LinkedIn")
  end

  test "requires authentication" do
    sign_out
    get job_applications_url
    assert_redirected_to new_session_url
  end

  # ---------- index ----------

  test "index lists the user's applications, with interviews and offers highlighted on top" do
    create_job_application(@user, title: "Designer", status: "interview")
    create_job_application(@user, title: "Analista", status: "offer")
    create_job_application(users(:two), title: "Segredo do Bruno")

    get job_applications_url
    assert_response :success
    assert_select "h1", "Candidaturas"
    assert_select "#ja-highlights .ja-highlight", 2
    assert_select "#ja-highlights .ja-highlight--interview", text: /Designer/
    assert_select "#ja-list .ja-row", 1
    assert_select "#ja-list .ja-row", text: /Programador Rails/
    assert_select "#ja-list select[name='transition[to]'] option[value=applied]"
    assert_no_match "Segredo do Bruno", response.body
  end

  test "index shows the next open task on the row" do
    create_task(@user, title: "Enviar portefólio", job_application: @application, due_at: 2.days.from_now)
    create_task(@user, title: "Mais tarde", job_application: @application, due_at: 9.days.from_now)

    get job_applications_url
    assert_select ".ja-row__task", text: /Enviar portefólio/
  end

  test "index loads 10 at a time, the next page lazily" do
    11.times { |i| create_job_application(@user, title: "Vaga #{i}", status: "applied") }

    get job_applications_url
    assert_select "#ja-list .ja-row", 10
    assert_select "turbo-frame#ja-page-2[loading=lazy][src*='page=2']"

    get job_applications_url(page: 2), headers: { "Turbo-Frame" => "ja-page-2" }
    assert_select "turbo-frame#ja-page-2 .ja-row", 2
    assert_select "turbo-frame#ja-page-3", 0
  end

  test "index filters by status tab and search" do
    create_job_application(@user, title: "Designer", status: "interview")

    get job_applications_url(status: "interview")
    assert_response :success
    assert_select "#ja-highlights", 0
    assert_select "#ja-list .ja-row", 1
    assert_select "#ja-list .ja-row", text: /Designer/
    assert_select ".tabs__link.is-active", /Entrevista/

    get job_applications_url(q: "rails")
    assert_select "#ja-list .ja-row", 1
    assert_select "#ja-list .ja-row", text: /Programador Rails/
  end

  test "index with no matches shows an empty state" do
    get job_applications_url(status: "offer")
    assert_response :success
    assert_select ".empty-state"
  end

  test "index without applications shows an empty state" do
    @application.destroy!
    get job_applications_url
    assert_response :success
    assert_select ".empty-state"
    assert_select "#ja-list", 0
  end

  test "index ignores invalid params" do
    get job_applications_url(view: "<script>", status: "hired", page: "-3")
    assert_response :success
    assert_select "#ja-list .ja-row", 1
  end

  # ---------- show ----------

  test "show renders the transitions, history and tasks" do
    task = create_task(@user, title: "Preparar CV", job_application: @application, task_type: "job")

    get job_application_url(@application)
    assert_response :success
    assert_select "h1", "Programador Rails"
    assert_select ".badge--saved"
    assert_select "form.ja-transition", 2
    assert_select "form.ja-transition input[name='transition[to]'][value='applied']"
    assert_select "form.ja-transition input[type=checkbox][name='transition[create_follow_up]']"
    assert_select ".timeline .timeline__item", 1
    assert_select ".timeline", text: /Vi no LinkedIn/
    assert_select "a[href=?]", task_path(task), text: "Preparar CV"
    assert_select "form[action=?]", create_task_job_application_path(@application)
    assert_select "form[action=?]", job_application_job_application_events_path(@application)
  end

  test "show offers an interview date when interview is the next step" do
    @application.update!(status: "applied")
    get job_application_url(@application)
    assert_select "input[type='datetime-local'][name='transition[interview_at]']"
  end

  test "show for a closed application has no transitions" do
    @application.update!(status: "rejected")
    get job_application_url(@application)
    assert_response :success
    assert_select "form.ja-transition", 0
    assert_select ".ja-closed"
  end

  test "show displays the job listing with an external link" do
    listing = @user.job_listings.create!(title: "Programador Rails", company_name: "Alfa", location: "Porto",
                                        url: "https://example.com/jobs/42")
    @application.update!(job_listing: listing)

    get job_application_url(@application)
    assert_select "a[href='https://example.com/jobs/42'][target=_blank][rel='noopener noreferrer']", text: /Abrir vaga/
    assert_match "Porto", response.body
  end

  test "show explains when there is no listing" do
    get job_application_url(@application)
    assert_select ".ja-listing__missing"
  end

  # ---------- new / create ----------

  test "new renders the manual form" do
    get new_job_application_url
    assert_response :success
    assert_select "form input[name='job_application[title]']"
    assert_select "input[name='job_application[job_listing_id]']", 0
  end

  test "new from a listing prefills the form" do
    listing = create_listing
    get new_job_application_url(job_listing_id: listing.id)
    assert_response :success
    assert_select "input[name='job_application[title]'][value='Backend Ruby']"
    assert_select "input[type=hidden][name='job_application[job_listing_id]'][value=?]", listing.id.to_s
  end

  test "new from a listing that already has an application redirects to it" do
    listing = create_listing
    @application.update!(job_listing: listing)
    get new_job_application_url(job_listing_id: listing.id)
    assert_redirected_to job_application_url(@application)
  end

  test "new with another user's listing is not found" do
    get new_job_application_url(job_listing_id: create_listing(users(:two)).id)
    assert_response :not_found
  end

  test "create a manual application" do
    assert_difference -> { @user.job_applications.count } => 1, -> { JobApplicationEvent.count } => 1 do
      post job_applications_url, params: { job_application: { title: "Analista", company_name: "Beta", notes: "Híbrido" } }
    end
    application = @user.job_applications.order(:id).last
    assert_redirected_to job_application_url(application)
    assert_equal "Candidatura registada como enviada.", flash[:notice]
    assert application.applied?
    assert_not_nil application.applied_at
    assert_equal "applied", application.job_application_events.last.event_type
    assert_equal 0, application.tasks.count
    assert AuditLog.exists?(action: "job_application.created", resource_id: application.id)
  end

  test "create ignores a status param" do
    post job_applications_url, params: { job_application: { title: "Analista", status: "offer" } }
    assert @user.job_applications.order(:id).last.applied?
  end

  test "create with invalid data re-renders the form" do
    assert_no_difference -> { JobApplication.count } do
      post job_applications_url, params: { job_application: { title: "" } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  test "create from a listing prefills and does not duplicate" do
    listing = create_listing

    assert_difference -> { @user.job_applications.count } => 1 do
      post job_applications_url, params: { job_application: { job_listing_id: listing.id } }
    end
    application = @user.job_applications.find_by!(job_listing: listing)
    assert_equal "Backend Ruby", application.title
    assert_equal "Gama", application.company_name

    assert_no_difference -> { JobApplication.count } do
      post job_applications_url, params: { job_application: { job_listing_id: listing.id } }
    end
    assert_redirected_to job_application_url(application)
    assert_equal "Já tinhas uma candidatura para esta vaga.", flash[:notice]
  end

  test "create with another user's listing is not found" do
    foreign = create_listing(users(:two))
    assert_no_difference -> { JobApplication.count } do
      post job_applications_url, params: { job_application: { job_listing_id: foreign.id, title: "X" } }
    end
    assert_response :not_found
  end

  # ---------- edit / update ----------

  test "edit renders the form" do
    get edit_job_application_url(@application)
    assert_response :success
    assert_select "input[name='job_application[title]'][value='Programador Rails']"
  end

  test "update changes details but never the status" do
    patch job_application_url(@application),
          params: { job_application: { title: "Programadora Rails", notes: "Nova nota", status: "offer" } }
    assert_redirected_to job_application_url(@application)
    @application.reload
    assert_equal "Programadora Rails", @application.title
    assert_equal "Nova nota", @application.notes
    assert @application.saved?
    assert AuditLog.exists?(action: "job_application.updated", resource_id: @application.id)
  end

  test "update with invalid data re-renders edit" do
    patch job_application_url(@application), params: { job_application: { title: "" } }
    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_equal "Programador Rails", @application.reload.title
  end

  # ---------- destroy ----------

  test "destroy removes the application and its history" do
    assert_difference -> { JobApplication.count } => -1, -> { JobApplicationEvent.count } => -1 do
      delete job_application_url(@application)
    end
    assert_redirected_to job_applications_url
    assert AuditLog.exists?(action: "job_application.deleted", resource_id: @application.id)
  end

  # ---------- transition ----------

  test "transition to applied with follow-up" do
    assert_difference -> { JobApplicationEvent.count } => 1, -> { @user.tasks.count } => 1 do
      patch transition_job_application_url(@application),
            params: { transition: { to: "applied", create_follow_up: "1", notes: "Via email" } }
    end
    assert_redirected_to job_application_url(@application)
    assert_match "Candidatura enviada", flash[:notice]
    assert_match "Follow-up: Programador Rails", flash[:notice]
    @application.reload
    assert @application.applied?
    assert_not_nil @application.applied_at
    assert_equal "Via email", @application.job_application_events.last.notes
  end

  test "transition to applied with a backdated send date" do
    patch transition_job_application_url(@application),
          params: { transition: { to: "applied", occurred_at: "2026-09-20T09:15", create_follow_up: "0" } }
    assert_equal Time.zone.local(2026, 9, 20, 9, 15), @application.reload.applied_at
  end

  test "transition to interview with a date creates the interview task" do
    @application.update!(status: "applied")
    interview_at = 4.days.from_now.change(sec: 0)
    patch transition_job_application_url(@application),
          params: { transition: { to: "interview", interview_at: interview_at.strftime("%Y-%m-%dT%H:%M") } }

    task = @user.tasks.find_by!(title: "Entrevista: Programador Rails")
    assert_equal interview_at, task.starts_at
    assert_equal 1, task.reminders.count
  end

  test "forbidden transition is refused with an alert" do
    assert_no_difference -> { JobApplicationEvent.count } do
      patch transition_job_application_url(@application), params: { transition: { to: "offer" } }
    end
    assert_redirected_to job_application_url(@application)
    assert_match "Não é possível passar", flash[:alert]
    assert @application.reload.saved?
  end

  test "changing the status from the list answers in place" do
    patch transition_job_application_url(@application), params: { transition: { to: "applied" }, return_to: "index" }, as: :turbo_stream
    assert_response :success
    assert_match %(action="prepend" target="ja-list"), response.body
    assert_match "Candidatura enviada", response.body
    assert @application.reload.applied?

    patch transition_job_application_url(@application), params: { transition: { to: "interview" }, return_to: "index" }, as: :turbo_stream
    assert_match %(action="prepend" target="ja-highlights"), response.body
  end

  test "undoes the last status change, from the list or the page" do
    JobApplications::Transition.call(@application, to: "applied")
    JobApplications::Transition.call(@application, to: "interview")

    get job_applications_url
    assert_select "#ja-highlights option[value=revert]", /Voltar a «Candidatura enviada»/

    patch transition_job_application_url(@application), params: { transition: { to: "revert" }, return_to: "index" }, as: :turbo_stream
    assert @application.reload.applied?
    assert_match %(action="prepend" target="ja-list"), response.body
    assert_equal %w[saved applied], @application.job_application_events.select(&:status_event?).map(&:event_type)

    patch transition_job_application_url(@application), params: { transition: { to: "rejected" } }
    patch transition_job_application_url(@application), params: { transition: { to: "revert" } }
    assert_redirected_to job_application_url(@application)
    assert @application.reload.applied?
  end

  test "undo still works when the status event was deleted from the history" do
    JobApplications::Transition.call(@application, to: "applied")
    JobApplications::Transition.call(@application, to: "interview")
    @application.job_application_events.find_by(event_type: "interview").destroy!

    patch transition_job_application_url(@application), params: { transition: { to: "revert" } }
    assert @application.reload.applied?
    assert_equal 1, @application.job_application_events.where(event_type: "applied").count
  end

  test "nothing to undo on a new application" do
    patch transition_job_application_url(@application), params: { transition: { to: "revert" } }
    assert_match "Não há nenhuma mudança", flash[:alert]
    assert @application.reload.saved?
  end

  test "transition from the list without Turbo returns to the index" do
    patch transition_job_application_url(@application), params: { transition: { to: "applied" }, return_to: "index" }
    assert_redirected_to job_applications_url
  end

  test "transition ignores unknown return_to values" do
    patch transition_job_application_url(@application),
          params: { transition: { to: "applied" }, return_to: "https://evil.example.com" }
    assert_redirected_to job_application_url(@application)
  end

  # ---------- create_task ----------

  test "create_task creates a linked job task and opens its edit page" do
    assert_difference -> { @user.tasks.count } => 1 do
      post create_task_job_application_url(@application)
    end
    task = @user.tasks.order(:id).last
    assert_redirected_to edit_task_url(task)
    assert_equal "Candidatar-me: Programador Rails", task.title
    assert_equal @application, task.job_application
    assert task.type_job?
  end

  # ---------- authorization ----------

  test "another user cannot see or change the application" do
    sign_out
    sign_in_as(users(:two))

    get job_application_url(@application)
    assert_response :not_found
    get edit_job_application_url(@application)
    assert_response :not_found
    patch job_application_url(@application), params: { job_application: { title: "Hack" } }
    assert_response :not_found
    patch transition_job_application_url(@application), params: { transition: { to: "applied" } }
    assert_response :not_found
    assert_no_difference -> { Task.count } do
      post create_task_job_application_url(@application)
    end
    assert_response :not_found
    assert_no_difference -> { JobApplication.count } do
      delete job_application_url(@application)
    end
    assert_response :not_found

    @application.reload
    assert_equal "Programador Rails", @application.title
    assert @application.saved?
  end

  private
    def create_listing(user = @user)
      user.job_listings.create!(title: "Backend Ruby", company_name: "Gama", location: "Lisboa",
                                url: "https://example.com/jobs/#{SecureRandom.hex(4)}")
    end
end
