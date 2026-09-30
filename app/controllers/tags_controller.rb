class TagsController < ApplicationController
  before_action :set_tag, only: %i[edit update destroy]

  def index
    @tags = Current.user.tags.with_task_counts.alphabetical.to_a
  end

  def new
    @tag = Current.user.tags.new(color: Tag::COLORS.first)
  end

  def create
    @tag = Current.user.tags.new(tag_params)
    if @tag.save
      AuditLog.record("tag.created", resource: @tag, name: @tag.name)
      redirect_to tags_path, notice: "Etiqueta “#{@tag.name}” criada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    previous_name = @tag.name
    if @tag.update(tag_params)
      AuditLog.record("tag.updated", resource: @tag, name: @tag.name, previous_name: previous_name)
      redirect_to tags_path, notice: "Etiqueta “#{@tag.name}” atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @tag.destroy!
    AuditLog.record("tag.destroyed", resource: @tag, name: @tag.name)
    redirect_to tags_path, notice: "Etiqueta “#{@tag.name}” eliminada.", status: :see_other
  end

  private
    def set_tag
      @tag = Current.user.tags.find(params[:id])
    end

    def tag_params
      params.expect(tag: [ :name, :color ])
    end
end
