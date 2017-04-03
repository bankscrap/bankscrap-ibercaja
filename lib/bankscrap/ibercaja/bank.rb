require 'bankscrap'

require 'json'
require 'base64'
require 'tempfile'
require 'digest'

module Bankscrap
  module Ibercaja
    class Bank < ::Bankscrap::Bank
      BASE_ENDPOINT       = 'https://ewm.ibercajadirecto.com/'.freeze
      POST_AUTH_ENDPOINT  = BASE_ENDPOINT + 'api/usuarios/iniciarsesion'
      PRODUCTS_ENDPOINT   = BASE_ENDPOINT + 'api/cuentas'

      REQUIRED_CREDENTIALS  = [:dni, :password]

      def initialize(credentials = {})
        super do
          @password = @password.to_s
        end
      end

      def balances
        log 'get_balances'
        balances = {}
        total_balance = 0
        @accounts.each do |account|
          balances[account.description] = account.balance
          total_balance += account.balance
        end

        balances['TOTAL'] = total_balance
        balances
      end

      def fetch_accounts
        log 'fetch_accounts'

        JSON.parse(get(PRODUCTS_ENDPOINT))['Productos'].map do |account|
          build_account(account)
        end.compact
      end

      def fetch_transactions_for(account, start_date: Date.today - 1.month, end_date: Date.today)
        log "fetch_transactions for #{account.id}"

        # The API allows any limit to be passed, but we better keep
        # being good API citizens and make a loop with a short limit
        params = {
          'request.cuenta' => account.id,
          'request.fechaInicio' => start_date.strftime('%Y/%m/%d'),
          'request.fechaFin' => end_date.strftime('%Y/%m/%d'),
        }


        request = get("#{PRODUCTS_ENDPOINT}/movimientos", params: params)
        json = JSON.parse(request)
        json['Movimientos'].map do |transaction|
          build_transaction(transaction, account)
        end
      end

      private

      def login
        add_headers(
          'Content-Type' => 'application/json; charset=utf-8',
          'AppID' => 'IbercajaAppV2Piloto',
          'version' => '2.4.8',
          'PlayBackMode' => 'Real',
          'Entidad' =>'2085',
          'Dispositivo' => 'IOSP',
          'Idioma' => 'es',
          'Canal' => 'MOV',
        )
        params = {"Usuario" => @dni, "Clave" => @password,"Tarjeta" => false}
        json = JSON.parse(post(POST_AUTH_ENDPOINT, fields: params.to_json))
        add_headers(
          'Ticket' => json['Ticket'],
          'Usuario' => @dni,
        )
      end

      # Build an Account object from API data
      def build_account(data)
        Account.new(
          bank: self,
          id: data['Numero'],
          name: data['Alias'],
          balance: Money.new(data['Saldo'] || 0, 'EUR'),
          available_balance: Money.new(data['Dispuesto'] || 0, 'EUR'),
          description: data['Alias'],
          iban: data['IBAN'],
        )
      end

      # Build a transaction object from API data
      def build_transaction(data, account)
        amount = Money.new(data['Importe'] || 0, 'EUR')
        Transaction.new(
          account: account,
          # There is no unique id in the json, so we MD5 the json to create one
          id: Digest::MD5.hexdigest(data.to_json),
          amount: amount,
          effective_date: Date.parse(data['FechaValor']),
          description: data['ConceptoMovimiento'] + ' ' + data['Registros'].join(' '),
          balance: Money.new(data['saldo'] || 0, 'EUR'),
        )
      end
    end
  end
end
