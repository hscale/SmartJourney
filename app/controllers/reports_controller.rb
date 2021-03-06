class ReportsController < ApplicationController

  before_filter :set_intro_colour
  before_filter :get_existing_report, :only => [:show, :update, :close, :comment]
  before_filter :instantiate_new_report, :only => [:new, :create]

  load_and_authorize_resource # this will only load a resource if there isn't one in @report already.
  skip_load_and_authorize_resource :only => [:close, :comment, :tags, :localtime] # do this manually.

  after_filter :send_new_report_alerts, :only => [:create]
  after_filter :send_report_update_alerts, :only => [:update]
  after_filter :send_report_close_alerts, :only => [:close]

  def index

    @intro_colour = "blue" # override the orange
    @future = params[:future] && params[:future].to_bool
    @selected_zones_only = current_user && params[:selected_zones_only] && params[:selected_zones_only].to_bool
    @tags_string = params[:tags] if params[:tags].present? # not blank.

    @tags = @tags_string.split(",").map {|t| t.strip.downcase }.uniq if @tags_string

    # NOTE: we get all reports (for current filters), and do any Limiting in the UI.
    # There wont be that many, and we need to show all of them on the map.

    if @future
      @reports = Report.future_reports
    else
      @reports = Report.open_reports
    end

    #TODO: can we do these in the sparql?
    @reports.select! { |r| current_user.in_zones?(r.zone) } if @selected_zones_only
    @reports.select! { |r| (r.tags & @tags).any? } if @tags # return where there's at least one match

    respond_to do |format|
      format.html
      format.js # feed list refresh.
      format.json { render :json => @reports } # map refersh
    end

  end

  def localtime
    respond_to do |format|
      format.json do
        render :json => {
          :time => Time.now.localtime.strftime("%H:%M"),
          :date => Time.now.localtime.strftime("%d %b")
        }
      end
    end
  end

  def new
    @reporting = true
  end

  def tags
    # expect param term to filter
    term = params[:term] || ""

    query = "SELECT DISTINCT ?tag
    WHERE {
      ?report a <http://data.smartjourney.co.uk/def/Report> .
      ?report <http://data.smartjourney.co.uk/def/tag> ?tag .
      FILTER regex(?tag, \"^" + term + "\", \"i\")
    }
    ORDER BY ASC(?tag)
    "
    results = Tripod::SparqlClient::Query.select(query).collect{ |r| r["tag"]["value"] }
    # add in the curated ones.
    results += Report.curated_tags.select { |t| t.start_with?(term) }
    results = results.uniq.sort
    render :json => results
  end

  def create

    respond_to do |format|

      # POST /reports/
      format.html do
        @reporting = true # hide report it btn
        populate_report_from_params(params[:report], true, :create) if params[:report]
        @success = @report.save

        if @success
          flash[:notice] = 'successfully created report'
          redirect_to reports_url
        else
          render 'new'
        end
      end

      # POST /reports.json
      # POST /reports (with accept header)
      format.json do
        populate_report_from_params(params[:report], true, :create) if params[:report]
        @success = @report.save
        if @success
          render :json => @report, :status => :created
        else
          render :json => @report.errors, :status => :bad_request
        end
      end
    end

  end

  def show
    @reporting = true
    @comment = Comment.new
    @comments = @report.comments

    respond_to do |format|
      format.html
      format.json { render :json => @report } # bonus API
    end
  end

  def update
    respond_to do |format|
      format.html do
        @reporting = true
        populate_report_from_params(params[:report], false, :update) if params[:report]
        @success = @report.save

        if @success
          flash[:notice] = 'successfully updated report'
          redirect_to report_url(@report)
        else
          render 'show'
        end
      end

      format.json do
        # if calling via the api, the caller might not know the original start time (unlike in UI, where it's already populated in the form)
        # so if it's not supplied, set the begins_at in the params to the current begins_at
        params[:report][:incident_begins_at] ||= @report.incident_begins_at

        populate_report_from_params(params[:report], false, :update) if params[:report]
        @success = @report.save
        if @success
          head :ok
        else
          render :json => @report.errors, :status => :bad_request
        end
      end
    end
  end

  # PUT /reports/:id/close
  def close

    authorize! :update, @report # this is a non-restful action, so manually auth.

    @report.close! # this shouldn't ever fail. If it does it's an exception.
    @success = true

    respond_to do |format|

      format.html do
        flash[:notice] = 'successfully closed report'
        redirect_to report_url(@report)
      end

      format.json do
        head :ok
      end
    end
  end

  private

  def populate_report_from_params(report_params, set_creator = false, action = :create)
    @report.latitude = params[:report][:latitude]
    @report.longitude = params[:report][:longitude]
    @report.description = params[:report][:description]
    @report.tags_string = params[:report][:tags_string]
    @report.creator = current_user if current_user && set_creator

    if can? action, :planned_incident
      @report.incident_begins_at = params[:report][:incident_begins_at].present? ? params[:report][:incident_begins_at] : Time.now
      @report.incident_ends_at = params[:report][:incident_ends_at] if params[:report][:incident_ends_at].present?
    end
  end

  def send_new_report_alerts
    if @success
      emails = @report.new_report_alert_recipients(current_user)

      # one queue item per email
      emails.each do |email|
        #note that we don't pass the screen name in here, as they might not be logged in (and the mailer doesn't use it).
        Delayed::Job.enqueue ReportAlertsJob.new(@report.uri, email, nil, :new)
      end
    end
  end

  def send_report_update_alerts
    if @success
      emails = @report.report_update_alert_recipients(current_user)

       # one queue item per email
      emails.each do |email|
        Delayed::Job.enqueue ReportAlertsJob.new(@report.uri, email, current_user.screen_name, :update)
      end
    end
  end

  def send_report_close_alerts
    if @success
      emails = @report.report_update_alert_recipients(current_user)

      # one queue item per email
      emails.each do |email|
        Delayed::Job.enqueue ReportAlertsJob.new(@report.uri, email, current_user.screen_name, :close)
      end
    end
  end

  def get_existing_report
    uri = "http://data.smartjourney.co.uk/id/report/#{params[:id]}"
    @report = Report.find(uri)
  end

  def instantiate_new_report
    @report = Report.new()
  end

  def set_intro_colour
   @intro_colour = "orange"
  end

end