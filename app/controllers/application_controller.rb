class ::ApplicationController < ActionController::Base

  layout 'app'

  before_filter :sign_in_api_user

  protect_from_forgery

  rescue_from Exception, :with => :render_error
  rescue_from Tripod::Errors::ResourceNotFound, :with => :render_not_found
  rescue_from CanCan::AccessDenied do |exception|
    respond_to do |format|
      format.html {redirect_to root_url, :alert => exception.message}
      format.json {head :unauthorized}
    end
  end

  private

  def render_not_found(e)
    @intro_colour = "red"
    Rails.logger.info(e)
    respond_to do |format|
      format.html {render :template => 'errors/not_found' }
      format.json {head :not_found}
    end
  end

  def render_error(e)
    @intro_colour = "red"
    Rails.logger.info(e)
    unless Rails.env.development?
      respond_to do |format|
        format.html {render :template => 'errors/error' }
        format.json {head 500}
      end
    else
      # in dev mode - reraise so we see it.
      raise e
    end
  end

  def sign_in_api_user
    if request.headers['api-key']
      user = User.where(:api_key => request.headers['api-key']).first
      if user
        sign_in user
      end
    end
  end

  def current_ability
    # pass the request into the Ability.
    @current_ability ||= Ability.new(current_user, request.format)
  end

end
