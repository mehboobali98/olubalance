# frozen_string_literal: true

class TransactionsController < ApplicationController
  include Pagy::Backend

  before_action :authenticate_user!
  before_action :find_account
  before_action :find_transaction, only: %i[edit update show destroy]
  before_action :transfer_accounts, only: %i[index]
  before_action :check_account_change, only: [:index]

  # Index action to render all transactions
  def index
    # @query = session[:query]
    # @order_by = permitted_column_name(session[:order_by])
    # @direction = permitted_direction(session[:direction])
    # @page = (session[:page] || 1).to_i

    # if params[:column].present?
    #   transactions = @account.transactions.with_attached_attachment.includes(:transaction_balance).order(pending: :desc, "#{params[:column]}" => "#{params[:direction]}", id: :desc)
    # else
    #   transactions = @account.transactions.with_attached_attachment.includes(:transaction_balance).order(pending: :desc, trx_date: :desc, id: :desc)
    # end

    session['filters'] ||= {}
    session['filters'].merge!(filter_params)

    @transactions = @account.transactions.with_attached_attachment.includes(:transaction_balance)
                            .then { search_by_description _1 }
                            .then { apply_pending_order _1 }
                            .then { apply_order _1 }
                            .then { apply_id_order _1 }

    # transactions = @account.transactions.order(pending: :desc, @order_by => @direction, id: :desc)
    # transactions = transactions.search(@query) if @query.present?
    # pages = (transactions.count / Pagy::DEFAULT[:items].to_f).ceil

    # @page = 1 if @page > pages
    @pagy, @transactions = pagy(@transactions)
    @transactions = @transactions.decorate

    @stashes = @account.stashes.order(id: :asc).decorate
    @stashed = @account.stashes.sum(:balance)

    respond_to do |format|
      format.html # index.html.erb
      format.xml { render xml: @transactions }
    end
  end

  # New action for creating transaction
  def new
    @transaction = @account.transactions.build.decorate

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render xml: @transaction }
    end
  end

  # Create action saves the trasaction into database
  def create
    @transaction = @account.transactions.build(transaction_params).decorate

    if @transaction.save
      redirect_to account_transactions_path, notice: 'Transaction was successfully created.'
    else
      render action: 'new'
    end
  end

  # Edit action retrieves the transaction and renders the edit page
  def edit
  end

  # Update action updates the transaction with the new information
  def update
    respond_to do |format|
      if @transaction.update(transaction_params)
        format.html { redirect_to account_transactions_path, notice: 'Transaction was successfully updated.' }
        format.xml { head :ok }
      else
        format.html { render action: 'edit' }
        format.xml { render xml: @transaction.errors, status: :unprocessable_entity }
      end
    end
  end

  # The show action renders the individual transaction after retrieving the the id
  def show
    respond_to do |format|
      format.html # show.html.erb
      format.xml { render xml: @transaction }
    end
  end

  # The destroy action removes the transaction permanently from the database
  def destroy
    @transaction.destroy

    respond_to do |format|
      format.html { redirect_to(account_transactions_url) }
      format.xml { head :ok }
    end
  end

  private

  def permitted_column_name(column_name)
    %w[trx_date description amount].find { |permitted| column_name == permitted } || 'trx_date'
  end

  def permitted_direction(direction)
    %w[asc desc].find { |permitted| direction == permitted } || 'desc'
  end

  def filter_params
    params.permit(:description, :column, :direction)
  end

  def transaction_params
    params.require(:transaction) \
          .permit(:trx_date, :description, :amount, :trx_type, :memo, :attachment, :page, :pending, :locked, :transfer, :account_id)
  end

  def search_by_description(scope)
    session['filters']['description'].present? ? scope.where('UPPER(description) like UPPER(?)', "%#{session['filters']['description']}%") : scope
  end

  def apply_pending_order(scope)
    scope.order(pending: :desc)
  end

  def apply_order(scope)
    scope.order(session['filters'].slice('column', 'direction').values.join(' '))
  end

  def apply_id_order(scope)
    scope.order(id: :desc)
  end

  def check_account_change
    # If there is no account ID stored in the session, set it to the current account
    if session[:current_account_id].nil? || session[:current_account_id] != @account.id
      session[:current_account_id] = @account.id
      session['filters'] = {} # Clear filters when the account is set or changed
    end
  end

  def find_account
    @account = current_user.accounts.find(params[:account_id]).decorate
    respond_to do |format|
      if @account.active?
        format.html
      else
        format.html { redirect_to accounts_inactive_path, notice: 'Account is inactive' }
      end
    end
  end

  def transfer_accounts
    account_id = params[:account_id]
    @transfer_accounts = current_user.accounts.where('active = ?', 'true').where('account_type != ?', 'credit').where(
      'id != ?', account_id
    ).decorate
  end

  def find_transaction
    @transaction = @account.transactions.find(params[:id]).decorate
  end
end
