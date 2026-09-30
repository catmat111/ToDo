class LinksController < ApplicationController
  # Owner-scoped finders for every type a Link can be attached to (Link::LINKABLE_TYPES).
  LINKABLE_SCOPES = { "Task" => :tasks, "JobApplication" => :job_applications }.freeze

  def create
    @linkable = find_linkable
    @link = Current.user.links.new(link_params.except(:linkable_type, :linkable_id).merge(linkable: @linkable))

    if @link.save
      AuditLog.record("link.created", resource: @link, linkable_type: @linkable.class.name,
                                      linkable_id: @linkable.id, host: @link.host)
      redirect_back_or_to @linkable, notice: "Link adicionado."
    else
      redirect_back_or_to @linkable, alert: "Não foi possível adicionar o link: #{@link.errors.full_messages.to_sentence}."
    end
  end

  def destroy
    @link = Current.user.links.find(params[:id])
    linkable = @link.linkable
    @link.destroy!
    AuditLog.record("link.destroyed", resource: @link, linkable_type: @link.linkable_type,
                                      linkable_id: @link.linkable_id, host: @link.host)
    redirect_back_or_to (linkable || root_path), notice: "Link removido.", status: :see_other
  end

  private
    def link_params
      params.expect(link: [ :linkable_type, :linkable_id, :url, :label ])
    end

    # Only the current user's tasks/applications can receive links; anything else is a 404.
    def find_linkable
      association = LINKABLE_SCOPES[link_params[:linkable_type].to_s]
      raise ActiveRecord::RecordNotFound, "Tipo de recurso inválido" unless association && Link::LINKABLE_TYPES.include?(link_params[:linkable_type])

      Current.user.public_send(association).find(link_params[:linkable_id])
    end
end
