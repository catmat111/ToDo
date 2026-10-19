# Calendar events (meetings, dinners…): created from the calendar or the chat, edited by
# clicking them on the calendar.
class EventsController < ApplicationController
  before_action :set_event, only: %i[edit update destroy]

  def new
    date = Date.iso8601(params[:date]) rescue Time.zone.today
    @event = Current.user.events.new(starts_at: date.in_time_zone.change(hour: 9), ends_at: date.in_time_zone.change(hour: 10))
  end

  def create
    @event = Current.user.events.new(event_params)
    if @event.save
      AuditLog.record("event.created", resource: @event, title: @event.title)
      redirect_to calendar_for(@event), notice: "Evento «#{@event.title}» adicionado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @event.update(event_params)
      AuditLog.record("event.updated", resource: @event, fields: @event.previous_changes.keys - %w[updated_at])
      redirect_to calendar_for(@event), notice: "Evento atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @event.destroy!
    AuditLog.record("event.destroyed", resource: @event, title: @event.title)
    redirect_to calendar_for(@event), notice: "Evento «#{@event.title}» eliminado.", status: :see_other
  end

  private
    def set_event
      @event = Current.user.events.find(params[:id])
    end

    def event_params
      params.expect(event: [ :title, :starts_at, :ends_at, :all_day, :location, :notes ])
    end

    def calendar_for(event)
      calendar_path(date: event.first_day.iso8601)
    end
end
