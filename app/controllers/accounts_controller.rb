# Fat Free CRM
# Copyright (C) 2008-2010 by Michael Dvorkin
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#------------------------------------------------------------------------------

class AccountsController < ApplicationController
  before_filter :require_user
  before_filter :set_current_tab, :only => [ :index, :show ]
  before_filter :attach, :only => :attach
  before_filter :discard, :only => :discard
  before_filter :auto_complete, :only => :auto_complete
  after_filter  :update_recently_viewed, :only => :show

  auto_complete_for :tag, :name

  # GET /accounts
  # GET /accounts.xml                                             HTML and AJAX
  #----------------------------------------------------------------------------
  def index
    @accounts = get_accounts(:page => params[:page])

    respond_to do |format|
      format.html # index.html.haml
      format.js   # index.js.rjs
      format.xml  { render :xml => @accounts }
    end
  end

  # GET /accounts/1
  # GET /accounts/1.xml                                                    HTML
  #----------------------------------------------------------------------------
  def show
    @account = Account.my(@current_user).find(params[:id])
    @stage = Setting.unroll(:opportunity_stage)
    @comment = Comment.new
    
    @timeline = Timeline.find(@account)

    respond_to do |format|
      format.html # show.html.haml
      format.xml  { render :xml => @account }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html, :xml)
  end

  # GET /accounts/new
  # GET /accounts/new.xml                                                  AJAX
  #----------------------------------------------------------------------------
  def new
    @account = Account.new(:user => @current_user, :access => Setting.default_access)
    @users = User.except(@current_user).active.by_name.all
    if params[:related]
      model, id = params[:related].split("_")
      instance_variable_set("@#{model}", model.classify.constantize.find(id))
    end

    respond_to do |format|
      format.js   # new.js.rjs
      format.xml  { render :xml => @account }
    end
  end

  # GET /accounts/1/edit                                                   AJAX
  #----------------------------------------------------------------------------
  def edit
    @account = Account.my(@current_user).find(params[:id])
    @users = User.except(@current_user).active.by_name.all
    if params[:previous] =~ /(\d+)\z/
      @previous = Account.my(@current_user).find($1)
    end

  rescue ActiveRecord::RecordNotFound
    @previous ||= $1.to_i
    respond_to_not_found(:js) unless @account
  end

  # POST /accounts
  # POST /accounts.xml                                                     AJAX
  #----------------------------------------------------------------------------
  def create
    @account = Account.new(params[:account])
    
    respond_to do |format|
      if @account.save_with_permissions(params[:users])        
        # None: account can only be created from the Accounts index page, so we 
        # don't have to check whether we're on the index page.
        @accounts = get_accounts
        format.js   # create.js.rjs
        format.xml  { render :xml => @account, :status => :created, :location => @account }
      else
        @users = User.except(@current_user).active.by_name.all
        format.js   # create.js.rjs
        format.xml  { render :xml => @account.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /accounts/1
  # PUT /accounts/1.xml                                                    AJAX
  #----------------------------------------------------------------------------
  def update
    @account = Account.my(@current_user).find(params[:id])

    respond_to do |format|
      if @account.update_with_permissions(params[:account], params[:users])        
        format.js
        format.xml  { head :ok }
      else
        @users = User.except(@current_user).active.by_name.all # Need it to redraw [Edit Account] form.
        format.js
        format.xml  { render :xml => @account.errors, :status => :unprocessable_entity }
      end
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:js, :xml)
  end

  # DELETE /accounts/1
  # DELETE /accounts/1.xml                                        HTML and AJAX
  #----------------------------------------------------------------------------
  def destroy
    @account = Account.my(@current_user).find(params[:id])
    @account.destroy if @account

    respond_to do |format|
      format.html { respond_to_destroy(:html) }
      format.js   { respond_to_destroy(:ajax) }
      format.xml  { head :ok }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html, :js, :xml)
  end

  # GET /accounts/search/query                                             AJAX
  #----------------------------------------------------------------------------
  def search
    @accounts = get_accounts(:query => params[:query], :page => 1)

    respond_to do |format|
      format.js   { render :action => :index }
      format.xml  { render :xml => @accounts.to_xml }
    end
  end

  # POST /accounts/filter                                                  AJAX
  #----------------------------------------------------------------------------
  def filter
    session[:filter_by_account_tags] = params[:tags] if params.has_key?(:tags)
    @accounts = get_accounts(:page => 1) # Start one the first page.
    render :action => :index
  end

  # PUT /accounts/1/attach
  # PUT /accounts/1/attach.xml                                             AJAX
  #----------------------------------------------------------------------------
  # Handled by before_filter :attach, :only => :attach

  # PUT /accounts/1/discard
  # PUT /accounts/1/discard.xml                                            AJAX
  #----------------------------------------------------------------------------
  # Handled by before_filter :discard, :only => :discard

  # POST /accounts/auto_complete/query                                     AJAX
  #----------------------------------------------------------------------------
  # Handled by before_filter :auto_complete, :only => :auto_complete

  # GET /accounts/options                                                 AJAX
  #----------------------------------------------------------------------------
  def options
    unless params[:cancel].true?
      @per_page = @current_user.pref[:accounts_per_page] || Account.per_page
      @outline  = @current_user.pref[:accounts_outline]  || Account.outline
      @sort_by  = @current_user.pref[:accounts_sort_by]  || Account.sort_by
    end
  end

  # POST /accounts/redraw                                                 AJAX
  #----------------------------------------------------------------------------
  def redraw
    @current_user.pref[:accounts_per_page] = params[:per_page] if params[:per_page]
    @current_user.pref[:accounts_outline]  = params[:outline]  if params[:outline]
    @current_user.pref[:accounts_sort_by]  = Account::sort_by_map[params[:sort_by]] if params[:sort_by]
    @accounts = get_accounts(:page => 1)
    render :action => :index
  end

  # PUT /accounts/1/add_tag
  def add_tag
    @owner = @account = Account.my(@current_user).find(params[:id])
    tag_list = params[:tag][:name]
    @account.add_tag(tag_list)
    
    respond_to do |format|
      format.html { redirect_to account_path(@account)}
      format.js { render :template => 'common/add_tag' }
    end
  end

  # PUT /leads/1/delete_tag
  def delete_tag
    @owner = @account = Account.my(@current_user).find(params[:id])
    @account.delete_tag(params[:tag])
    respond_to do |format|
      format.html {redirect_to account_path(@account) }
      format.js { render :template => 'common/delete_tag' }
    end
  end

  private
  #----------------------------------------------------------------------------
  def get_accounts(options = { :page => nil, :query => nil })
    self.current_page = options[:page] if options[:page]
    self.current_query = options[:query] if options[:query]

    records = {
      :user => @current_user,
      :order => @current_user.pref[:accounts_sort_by] || Account.sort_by
    }
    pages = {
      :page => current_page,
      :per_page => @current_user.pref[:accounts_per_page]
    }

    # Call :get_accounts hook and return its output if any.
    accounts = hook(:get_accounts, self, :records => records, :pages => pages)
    return accounts.last unless accounts.empty?

    # Default processing if no :get_accounts hooks are present.
    Account.search_and_filter(records.merge(:query => current_query,
                                            :tags => session[:filter_by_account_tags])).paginate(pages)
  end

  #----------------------------------------------------------------------------
  def respond_to_destroy(method)
    if method == :ajax
      @accounts = get_accounts
      if @accounts.blank?
        @accounts = get_accounts(:page => current_page - 1) if current_page > 1
        render :action => :index and return
      end
      # At this point render default destroy.js.rjs template.
    else # :html request
      self.current_page = 1 # Reset current page to 1 to make sure it stays valid.
      flash[:notice] = "#{t(:asset_deleted, @account.name)}"
      redirect_to(accounts_path)
    end
  end

end
